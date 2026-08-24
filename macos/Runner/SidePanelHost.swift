import Cocoa
import FlutterMacOS
import os.log

/// MethodChannel host for the clipboard quick-paste side panel on macOS
/// (issue 04). Mirrors `FloatingOverlayHost`'s three-layer split, scoped
/// down to what this simpler, click-driven panel actually needs (no drag,
/// no context menu, no waveform, no stall-recovery watchdog -- the overlay's
/// watchdog exists because it repaints ~10Hz during recording and got
/// wedged in the wild; this panel repaints only on row-content changes).
///
/// - The MAIN engine talks to this host over `com.whispaste.side_panel`
///   (`updateSnapshot`; native replies with `rowClicked` / `hoverLeft` /
///   `hoverEntered`).
/// - This host relays snapshots to a dedicated second Flutter engine
///   (entrypoint `sidePanelMain`) over the private
///   `com.whispaste.side_panel_render` channel, and translates that
///   engine's `rowClicked` / `hoverLeft` back into the public contract.
/// - A thin `SidePanelSensorPanel` per connected `NSScreen` reports pointer
///   entry as `hoverEntered`; the main engine's `SidePanelService` reacts by
///   priming the paste target and pushing the first `updateSnapshot`, which
///   is what actually lazy-creates and shows the content panel here.
/// Tracks the pointer over the content panel's own view so the panel can
/// auto-close natively, independent of the render engine's own Flutter
/// `MouseRegion`.
///
/// Why this exists: the render engine's `MouseRegion.onExit` (relayed as
/// `hoverLeft`) is not reliable as the *sole* close trigger -- Flutter's
/// framework-level mouse tracking only learns a pointer is "inside" a
/// region from an actual pointer event delivered to that engine, and it's
/// not guaranteed one has been delivered by the time the user moves the
/// mouse back out (e.g. a dwell-then-immediate-leave with no click in
/// between). A genuine AppKit `NSTrackingArea` with `.activeAlways` +
/// `.inVisibleRect` -- the same combination `SidePanelSensorView` already
/// uses successfully for hover-*open* -- reconciles correctly against real
/// pointer motion regardless of what Flutter's own tracking believes, so
/// mirroring it here for hover-*close* gives the panel a reliable trigger
/// that doesn't depend on the render engine at all. Kept alongside (not
/// instead of) the Dart-driven `hoverLeft` relay: both converge on the same
/// public-channel call, so firing twice is a harmless no-op in
/// `SidePanelService.close()`.
private final class SidePanelContentHoverTracker: NSResponder {
  let onEntered: () -> Void
  let onExited: () -> Void

  init(onEntered: @escaping () -> Void, onExited: @escaping () -> Void) {
    self.onEntered = onEntered
    self.onExited = onExited
    super.init()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func mouseEntered(with event: NSEvent) { onEntered() }
  override func mouseExited(with event: NSEvent) { onExited() }
}

class SidePanelHost {
  /// Fixed content width -- there is no persisted/dragged position to
  /// restore (unlike the floating overlay), so no `OverlayDesignSpec`
  /// equivalent is needed; this is just wide enough for a title + subtitle
  /// row (see `WpSidePanelRowTile`).
  private static let contentWidth: CGFloat = 320

  /// Fixed content height (issue 08) -- enough to comfortably show a
  /// handful of rows (header + tab bar + search field + ~6 rows) without
  /// claiming the whole screen the way the panel used to. Clamped to the
  /// hovered monitor's own `visibleFrame.height` in [targetRect] for
  /// monitors shorter than this, so the panel never asks for more height
  /// than the screen actually has.
  private static let contentHeight: CGFloat = 640

  /// Slide-in/out duration -- fast enough to feel responsive to a
  /// deliberate hover, slow enough to read as motion rather than a snap.
  private static let slideDuration: TimeInterval = 0.22

  /// Grace period before the native content-hover-exit actually closes the
  /// panel -- mirrors `_closeGracePeriod` in `side_panel_render_entrypoint
  /// .dart` so both close triggers feel identical regardless of which one
  /// actually fires first.
  private static let closeGracePeriod: TimeInterval = 0.35

  private var channel: FlutterMethodChannel
  private var contentPanel: SidePanelContentPanel?
  private var sensors: [SidePanelSensorPanel] = []
  private var screenObserver: NSObjectProtocol?

  /// Whether the panel is currently slid into view. Distinguishes a genuine
  /// open/close transition (animate) from a content-only `updateSnapshot`
  /// push while already open (no animation, no re-order).
  private var isShown = false

  /// The screen the panel is currently anchored to -- set on hover-enter,
  /// read by the slide animation so it knows which edge to slide from/to.
  private var currentScreenFrame: NSRect?

  /// The app that was frontmost right before [slideIn] activated WhisPaste
  /// (issue 09), so [slideOut] can hand activation straight back to it. See
  /// `SidePanelContentPanel`'s doc comment and `activateForKeyboard` below.
  private var previousFrontApp: NSRunningApplication?

  private var renderEngine: FlutterEngine?
  private var renderViewController: FlutterViewController?
  private var renderChannel: FlutterMethodChannel?

  /// Flutter's own `flutter/lifecycle` channel into the render engine -- see
  /// [resumeRenderEngineLifecycle] for why this host has to drive it itself.
  private var renderLifecycleChannel: FlutterBasicMessageChannel?
  private var renderReady = false
  private var latestSnapshotArgs: [String: Any]?
  private var contentHoverTracker: SidePanelContentHoverTracker?
  private var nativeCloseTimer: Timer?

  /// Window during which the edge sensor strips ignore hover events --
  /// armed by [beginActivationSettleWindow] right before every app-
  /// activation change ([activateForKeyboard] / [restorePreviousFrontApp]).
  ///
  /// Activating a different app is a system-wide event that makes AppKit
  /// re-synthesize `mouseEntered` on the sensor strip even though the
  /// pointer never moved (see `SidePanelSensorView`'s doc comment on the
  /// self-sustaining flicker this causes). Both `slideIn` and `slideOut`
  /// trigger exactly one activation change each, so without this guard the
  /// spurious re-entry reopens (or reschedules closing) the panel, which
  /// itself calls `slideIn`/`slideOut` again, which activates again --
  /// looping until the pointer happens to actually leave the strip.
  /// Filtering sensor events for a short window after OUR OWN activation
  /// calls breaks the loop without weakening the strip's response to
  /// genuine pointer motion: 200ms is comfortably longer than AppKit's
  /// reconciliation but short enough that a real subsequent hover isn't
  /// perceptibly delayed.
  private static let activationSettleDelay: TimeInterval = 0.2
  private var suppressSensorEvents = false
  private var activationSettleTimer: Timer?

  private func beginActivationSettleWindow() {
    suppressSensorEvents = true
    activationSettleTimer?.invalidate()
    activationSettleTimer = Self.scheduleTimer(interval: Self.activationSettleDelay) { [weak self] in
      self?.suppressSensorEvents = false
    }
  }

  /// `Timer.scheduledTimer` only registers the timer in `.default` run loop
  /// mode. While the pointer is being tracked across the sensor strip --
  /// exactly the scenario [beginActivationSettleWindow] and
  /// [scheduleNativeClose] fire in -- AppKit can spend stretches of the main
  /// run loop in `.eventTrackingRunLoopMode`, which starves `.default`-mode
  /// timers entirely. A starved [activationSettleTimer] left
  /// `suppressSensorEvents` stuck `true` forever, which permanently disabled
  /// `onHoverEntered` (see `rebuildSensors`) -- the panel would stop
  /// responding to hover with no further feedback, exactly the "es reagiert
  /// nicht mehr" report this fixes. Scheduling into `.common` modes instead
  /// makes the timer fire during tracking too.
  private static func scheduleTimer(interval: TimeInterval, action: @escaping () -> Void) -> Timer {
    let timer = Timer(timeInterval: interval, repeats: false) { _ in action() }
    RunLoop.main.add(timer, forMode: .common)
    return timer
  }

  private static let logger = OSLog(subsystem: "com.whispaste", category: "SidePanelHost")

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.whispaste.side_panel", binaryMessenger: messenger)
    channel.setMethodCallHandler(handle)
    rebuildSensors()
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.rebuildSensors()
    }
  }

  // MARK: - Public channel (main engine <-> this host)

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateSnapshot":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      handleUpdateSnapshot(args)
      result(nil)

    case "destroy":
      teardown()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleUpdateSnapshot(_ args: [String: Any]) {
    let visible = args["visible"] as? Bool ?? false
    if visible && contentPanel == nil {
      ensurePanel()
    }

    latestSnapshotArgs = args
    if renderReady {
      renderChannel?.invokeMethod("updateSnapshot", arguments: args)
    }

    if visible && !isShown {
      isShown = true
      slideIn()
    } else if !visible && isShown {
      isShown = false
      slideOut()
    }
  }

  // MARK: - Slide animation

  /// Slides the (already-`orderFront`-able) panel from just off the
  /// monitor's edge to its resting position next to the sensor strip, then
  /// claims keyboard focus for the search field (issue 09).
  private func slideIn() {
    guard let panel = contentPanel, let screenFrame = currentScreenFrame else { return }

    // Remember the outgoing frontmost app before [activateForKeyboard] can
    // change it -- same reasoning as `SnippetPickerHost.show`.
    let front = NSWorkspace.shared.frontmostApplication
    previousFrontApp = front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front

    panel.setFrame(targetRect(for: screenFrame, shown: false), display: false)
    panel.orderFront(nil)
    resumeRenderEngineLifecycle()
    // Detach and reattach the render engine's view controller on EVERY
    // show, after `orderFront` -- see `SnippetPickerHost.show`'s doc
    // comment for the full mechanism this mirrors. `bootRenderEngine`
    // (called once, from `ensurePanel`) sets `panel.contentViewController`
    // exactly once and this panel is reused for the whole app session
    // (never recreated between opens), so without this line the reattach
    // that forces AppKit to redo the view's appearance cycle -- and, more
    // importantly, the display link Flutter's macOS engine keys off
    // `viewDidMoveToWindow` -- never fires again after the first open.
    // `slideOut`'s `orderOut` pauses that display link (the view stops
    // being on a visible window); a bare `orderFront` on the same
    // still-attached view controller does not retrigger the notification
    // that resumes it, so the panel keeps presenting whatever frame was
    // last rasterized -- confirmed live: typing/clicking updated the
    // underlying Dart state (visible again on the *next* open) but never
    // repainted while already open, exactly the "kein direktes Feedback
    // mehr" report this fixes.
    //
    // Note this is NOT what makes the panel repaint again after a close:
    // that is [resumeRenderEngineLifecycle]. The reattach only restores the
    // view's appearance cycle; with the engine's Dart-side lifecycle stuck
    // at `hidden` no amount of reattaching produces a frame, which is why
    // this line alone was not enough and the freeze survived it.
    if let vc = renderViewController {
      panel.contentViewController = nil
      panel.contentViewController = vc
    }

    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.slideDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(self.targetRect(for: screenFrame, shown: true), display: true)
    } completionHandler: { [weak self] in
      // Re-assert AFTER the activation this same call kicks off has
      // settled: `activateForKeyboard` below makes AppKit post
      // `NSApplicationWillBecomeActiveNotification`, and the embedder
      // answers that by re-sending `hidden` (see
      // [resumeRenderEngineLifecycle]), which would otherwise undo the
      // resume issued above a few milliseconds earlier.
      //
      // Guarded for the mirror image of the reason `slideOut`'s handler is:
      // if the panel was closed again while this animation ran, resuming
      // here would leave the engine painting an off-screen panel forever.
      guard let self, self.isShown else { return }
      self.resumeRenderEngineLifecycle()
    }

    // Claim key status and the first responder before activating -- see
    // `SnippetPickerHost.show` for why this order (not activate-then-key)
    // is what makes the activation race actually resolve in the panel's
    // favor.
    panel.makeKey()
    panel.makeFirstResponder(renderViewController?.view)
    activateForKeyboard()
  }

  /// Tells the render engine's Flutter framework that it is visible again.
  ///
  /// Unavoidable, because the embedder's own answer to "is this engine
  /// visible?" is wrong for a panel like this one. `FlutterEngine` derives
  /// the Dart-side `AppLifecycleState` from two APPLICATION-wide AppKit
  /// signals (see `handleWillBecomeActive` / `handleWillResignActive` /
  /// `handleDidChangeOcclusionState` in the embedder's `FlutterEngine.mm`):
  /// whether the app is active, and whether `NSApplication.occlusionState`
  /// contains `.visible`. This panel satisfies neither. WhisPaste runs
  /// window-less in the menu bar, so the moment [slideOut] hands activation
  /// back to the previous app, the embedder sends `AppLifecycleState.hidden`
  /// -- and `NSApplication.occlusionState` never reports `.visible` again
  /// for a `.borderless` / `.nonactivatingPanel` at `.popUpMenu` level, so
  /// the `_visible` flag those handlers gate on stays `NO` forever.
  ///
  /// That is not a cosmetic mislabel. Flutter's `SchedulerBinding` turns
  /// `framesEnabled` off in `hidden`, which makes `scheduleFrame()` a no-op:
  /// Dart keeps running (timers fire, `setState` marks the tree dirty) but
  /// no frame is ever built, rasterized or presented again. The panel
  /// freezes on its last rasterized frame -- confirmed live: the render
  /// engine went from `framesEnabled=true hasScheduledFrame=true` to
  /// `framesEnabled=false lifecycle=AppLifecycleState.hidden` within 500ms
  /// of the panel closing, and stayed there across every subsequent reopen.
  ///
  /// Worse, `handleWillBecomeActive` re-sends `hidden` (not `resumed`) on
  /// EVERY activation while `_visible` is `NO`, which is why the freeze
  /// needed a real app switch to show up and why reopening the panel could
  /// not shake it loose: each activation re-asserted the wrong state.
  ///
  /// So this host -- which is the only thing that actually knows whether the
  /// panel is on screen -- states it directly on the same channel the
  /// embedder uses. `ServicesBinding` parses these strings, so this is the
  /// framework's own supported contract, not a private hook.
  private func resumeRenderEngineLifecycle() {
    renderLifecycleChannel?.sendMessage("AppLifecycleState.resumed")
  }

  /// The other half of [resumeRenderEngineLifecycle]: once the panel is
  /// genuinely off screen again, tell the render engine so Flutter can stop
  /// scheduling frames for pixels nobody can see.
  ///
  /// Not merely tidiness. Now that this host asserts `resumed` itself, the
  /// embedder's own `hidden` message is no longer something to rely on --
  /// without this the engine would keep repainting at full frame rate for
  /// the entire app session after the first open, which is precisely the
  /// kind of idle background cost the hotkey-to-text budget cannot afford.
  /// Sending it from the slide-out completion handler (not at slide-out
  /// entry) keeps the closing animation's frames intact.
  private func suspendRenderEngineLifecycle() {
    renderLifecycleChannel?.sendMessage("AppLifecycleState.hidden")
  }

  /// Makes WhisPaste the active app so the search field can actually
  /// receive keystrokes, raising only this panel (not the main window).
  ///
  /// See `SnippetPickerHost.activateForKeyboard`'s doc comment for the full
  /// rationale -- `.nonactivatingPanel` only governs which of *this app's*
  /// windows may hold key status; macOS still routes physical keystrokes to
  /// the active application's process, so a panel of an inactive app stays
  /// keyboard-dead regardless of `makeKey()`. `.activateIgnoringOtherApps`
  /// (not the cooperative, macOS-14+ `activate(options:)`) is deliberate
  /// here too: a declined cooperative activation would degrade straight
  /// back to the keyboard-dead panel this exists to prevent.
  private func activateForKeyboard() {
    // Deliberately unconditional -- NOT gated on `NSApp.isActive`. That
    // guard used to skip the real activation whenever `NSApp.isActive`
    // already read `true`, but `panel.makeKey()` just above this call (on
    // a `.nonactivatingPanel` with `canBecomeKey == true`) can flip
    // `NSApp.isActive` to `true` *locally*, in-process, without WhisPaste
    // actually becoming the window server's foreground app -- confirmed via
    // live logging: `slideIn` reads `NSApp.isActive == false` on entry, then
    // `activateForKeyboard`, called a few lines later in the same call,
    // already reads `true`, despite `NSRunningApplication.current.activate`
    // never having run yet. The guard then skipped the one call that
    // actually raises the process to the foreground, leaving the panel
    // permanently keyboard/focus-dead (visible, but every click and
    // keystroke goes nowhere) -- exactly the "reagiert nicht mehr" report,
    // reproducible every time some other window had taken focus since
    // WhisPaste last launched (right after launch `NSApp.isActive` happens
    // to already be genuinely `true`, which is why the very first open
    // always worked). `.activate(options: .activateIgnoringOtherApps)` is a
    // harmless no-op when genuinely already frontmost, so there is no
    // upside to gating this at all.
    beginActivationSettleWindow()
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
  }

  /// Slides the panel back off-screen, then orders it out -- so it's
  /// actually invisible again once the animation settles, not just parked
  /// off to the side while still `orderFront`. Also hands activation back
  /// to whichever app was frontmost before [slideIn] activated WhisPaste,
  /// so the *next* `SidePanelService.open()` -> `prime()` call runs with
  /// WhisPaste not frontmost again (see [previousFrontApp]).
  private func slideOut() {
    guard let panel = contentPanel, let screenFrame = currentScreenFrame else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = Self.slideDuration
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().setFrame(self.targetRect(for: screenFrame, shown: false), display: true)
    } completionHandler: { [weak self, weak panel] in
      // Only finish the close if the panel is still meant to be closed.
      // This handler fires [slideDuration] after the close started, while
      // `beginActivationSettleWindow` only suppresses sensor events for
      // [activationSettleDelay] -- a shorter window. A pointer returning to
      // the sensor strip in that gap re-opens the panel (dwell + `slideIn`)
      // *before* this handler runs, and an unguarded handler would then
      // `orderOut` a panel the user just reopened and, worse, put its engine
      // back into `hidden` right after [slideIn] resumed it -- reproducing
      // exactly the freeze this whole change fixes, with no way out short of
      // another full close/reopen.
      guard let self, !self.isShown else { return }
      panel?.orderOut(nil)
      self.suspendRenderEngineLifecycle()
    }
    restorePreviousFrontApp()
  }

  /// Yields activation back to [previousFrontApp], restoring the "WhisPaste
  /// is not frontmost" invariant the next `SidePanelService.open()` ->
  /// `prime()` call depends on (`DesktopPasteHost.captureTarget()` clears
  /// the stored target whenever WhisPaste itself is frontmost).
  ///
  /// Cooperative activation on macOS 14+ -- unlike [activateForKeyboard],
  /// which must not risk being declined, a *giving away* of focus by the
  /// currently active app is exactly the case macOS grants. Mirrors
  /// `SnippetPickerHost.restorePreviousFrontApp`.
  private func restorePreviousFrontApp() {
    guard let previous = previousFrontApp else { return }
    previousFrontApp = nil
    guard !previous.isTerminated else { return }
    beginActivationSettleWindow()
    if #available(macOS 14.0, *) {
      previous.activate(options: [])
    } else {
      previous.activate(options: [.activateIgnoringOtherApps])
    }
  }

  /// The panel's resting frame ([shown]) or its just-off-the-edge staging
  /// frame ([!shown]) for the given monitor.
  ///
  /// Resting `x` is flush with the screen edge, not offset by
  /// [SidePanelSensorPanel.width]: the sensor strip only needs to be
  /// topmost while the content panel is off-screen, to catch the initial
  /// dwell-hover that opens it. Once shown, the content panel itself is
  /// ordered front (`slideIn`) and covers that same strip, so its own
  /// `SidePanelContentHoverTracker` takes over keeping the panel open for
  /// that whole area -- an offset here would leave a visible sliver of
  /// desktop between the panel and the screen edge for no remaining
  /// functional reason.
  ///
  /// Note that the `!shown` frame has NO intersection with [screenFrame] at
  /// all, which makes `NSWindow.screen` `nil` while the panel is parked. The
  /// embedder re-derives the render engine's `CVDisplayLink` from exactly
  /// that value (`_FlutterDisplayLink.updateScreen` in the engine's
  /// `FlutterDisplayLink.mm`) and unregisters the link when it reads `nil`,
  /// so a vsync request outstanding across this transition would be orphaned
  /// and the panel would never paint again. What keeps that from happening
  /// is [suspendRenderEngineLifecycle]: it turns the framework's
  /// `framesEnabled` off before the panel is parked, so no frame is ever
  /// requested while the frame is screen-less. That protection is NOT
  /// inherent to this geometry -- dropping the suspend, or making this panel
  /// animate its own *content* (rather than just its window position) across
  /// a close, re-arms the hazard.
  ///
  /// `y` centers the panel vertically within [screenFrame] (issue 08) --
  /// recomputed from [screenFrame] on every call, so hovering a
  /// different-height monitor recenters correctly for that monitor without
  /// any extra plumbing (this is called fresh from `positionPanel` on every
  /// `handleHoverEntered`). Height is clamped to `screenFrame.height` for a
  /// monitor shorter than [contentHeight], which also makes centering
  /// degrade gracefully to the old top-aligned, full-height behavior in
  /// that case (`y == screenFrame.minY` when `height == screenFrame.height`).
  private func targetRect(for screenFrame: NSRect, shown: Bool) -> NSRect {
    let x = shown ? screenFrame.minX : screenFrame.minX - Self.contentWidth
    let height = min(Self.contentHeight, screenFrame.height)
    let y = screenFrame.minY + (screenFrame.height - height) / 2
    return NSRect(x: x, y: y, width: Self.contentWidth, height: height)
  }

  // MARK: - Sensor strips (one per NSScreen)

  private func rebuildSensors() {
    sensors.forEach { $0.orderOut(nil) }
    sensors = NSScreen.screens.map { screen in
      SidePanelSensorPanel(
        screenFrame: screen.visibleFrame,
        onHoverEntered: { [weak self] in
          guard let self, !self.suppressSensorEvents else { return }
          self.handleHoverEntered(screenFrame: screen.visibleFrame)
        },
        onRawEnter: { [weak self] in
          guard let self, !self.suppressSensorEvents else { return }
          self.nativeCloseTimer?.invalidate()
        },
        onRawExit: { [weak self] in
          guard let self, !self.suppressSensorEvents else { return }
          self.scheduleNativeClose()
        }
      )
    }
    sensors.forEach { $0.orderFront(nil) }
  }

  private func handleHoverEntered(screenFrame: NSRect) {
    positionPanel(nextTo: screenFrame)
    channel.invokeMethod("hoverEntered", arguments: nil)
  }

  private func positionPanel(nextTo screenFrame: NSRect) {
    currentScreenFrame = screenFrame
    let rect = targetRect(for: screenFrame, shown: false)
    if let panel = contentPanel, !isShown {
      // Not currently shown -- safe to relocate without a visible jump
      // (e.g. the user hovered a different monitor's edge this time).
      panel.setFrame(rect, display: false)
    } else if contentPanel == nil {
      pendingFrame = rect
    }
  }

  private var pendingFrame: NSRect?

  // MARK: - Content panel + render engine

  private func ensurePanel() {
    let rect = pendingFrame ?? NSRect(x: 0, y: 0, width: Self.contentWidth, height: Self.contentHeight)
    pendingFrame = nil
    let panel = SidePanelContentPanel(frame: rect)
    contentPanel = panel
    bootRenderEngine()
    os_log("ensurePanel: panel created at %{public}@", log: Self.logger, type: .info, NSStringFromRect(rect))
  }

  private func bootRenderEngine() {
    guard let panel = contentPanel else { return }
    renderReady = false

    // macOS `runWithEntrypoint:` resolves the name only against the ROOT
    // library, so `sidePanelMain` is declared in Dart's main.dart -- see
    // that file's doc comment, mirrors `floatingOverlayMain`.
    let engine = FlutterEngine(name: "side_panel", project: nil)
    let didRun = engine.run(withEntrypoint: "sidePanelMain")
    os_log("bootRenderEngine: engine.run(sidePanelMain) -> %{public}@", log: Self.logger, type: .info, didRun ? "true" : "false")
    guard didRun else {
      renderEngine = nil
      return
    }

    let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    vc.backgroundColor = .clear

    let renderCh = FlutterMethodChannel(
      name: "com.whispaste.side_panel_render",
      binaryMessenger: engine.binaryMessenger
    )
    renderLifecycleChannel = FlutterBasicMessageChannel(
      name: "flutter/lifecycle",
      binaryMessenger: engine.binaryMessenger,
      codec: FlutterStringCodec.sharedInstance()
    )
    renderCh.setMethodCallHandler { [weak self] call, result in
      self?.handleRenderCall(call, result: result)
    }

    // See FloatingOverlayHost's doc comment for why contentViewController
    // (not a manually-added subview) is required for correct sizing.
    panel.contentViewController = vc

    let tracker = SidePanelContentHoverTracker(
      onEntered: { [weak self] in self?.nativeCloseTimer?.invalidate() },
      onExited: { [weak self] in self?.scheduleNativeClose() }
    )
    contentHoverTracker = tracker
    vc.view.addTrackingArea(
      NSTrackingArea(
        rect: vc.view.bounds,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: tracker,
        userInfo: nil
      )
    )

    renderEngine = engine
    renderViewController = vc
    renderChannel = renderCh
  }

  /// Native fallback close trigger -- see `SidePanelContentHoverTracker`'s
  /// doc comment for why this exists alongside the Dart-driven one. Routes
  /// through the exact same public-channel call the render engine's relay
  /// uses, so `SidePanelService.close()` is the single owner of the actual
  /// state transition either way.
  private func scheduleNativeClose() {
    nativeCloseTimer?.invalidate()
    nativeCloseTimer = Self.scheduleTimer(interval: Self.closeGracePeriod) { [weak self] in
      self?.channel.invokeMethod("hoverLeft", arguments: nil)
    }
  }

  private func handleRenderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      os_log("render engine ready -- flushing cached snapshot", log: Self.logger, type: .info)
      renderReady = true
      if let snap = latestSnapshotArgs {
        renderChannel?.invokeMethod("updateSnapshot", arguments: snap)
      }
      result(nil)

    case "rowClicked":
      os_log("rowClicked relayed to main engine: %{public}@", log: Self.logger, type: .info, String(describing: call.arguments))
      channel.invokeMethod("rowClicked", arguments: call.arguments)
      result(nil)

    case "hoverLeft":
      // Relay to the main engine; SidePanelService.close() replies with
      // updateSnapshot(visible: false), which is what actually triggers
      // slideOut() below -- keeps the single animate-then-orderOut path
      // instead of a second, uncoordinated immediate hide here.
      channel.invokeMethod("hoverLeft", arguments: nil)
      result(nil)

    case "reportError":
      if let args = call.arguments as? [String: Any], let message = args["message"] as? String {
        os_log("render engine reported an error: %{public}@", log: Self.logger, type: .error, message)
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Teardown

  private func teardown() {
    // Defensive: normally already nil by the time teardown runs (slideOut
    // already restored it), but this covers the panel being torn down
    // (e.g. the user disables the setting) while still shown/activated.
    restorePreviousFrontApp()
    if let obs = screenObserver {
      NotificationCenter.default.removeObserver(obs)
      screenObserver = nil
    }
    sensors.forEach { $0.orderOut(nil) }
    sensors = []
    nativeCloseTimer?.invalidate()
    nativeCloseTimer = nil
    activationSettleTimer?.invalidate()
    activationSettleTimer = nil
    suppressSensorEvents = false
    contentHoverTracker = nil
    renderChannel?.setMethodCallHandler(nil)
    renderLifecycleChannel = nil
    contentPanel?.close()
    contentPanel = nil
    renderViewController = nil
    renderChannel = nil
    renderEngine?.shutDownEngine()
    renderEngine = nil
    renderReady = false
    latestSnapshotArgs = nil
    isShown = false
    currentScreenFrame = nil
    channel.setMethodCallHandler(nil)
  }
}
