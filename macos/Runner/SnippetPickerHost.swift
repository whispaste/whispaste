import Carbon.HIToolbox
import Cocoa
import FlutterMacOS
import os.log

/// MethodChannel host for the Snippet-Picker on macOS (dictation-automations
/// ticket 06).
///
/// Same shell architecture as `FloatingButtonHost`/`FloatingOverlayHost`
/// (ADR 0002): the panel is a lifecycle-only shell hosting a **second Flutter
/// engine** (entrypoint `snippetPickerMain`) that paints the searchable
/// snippet list. Unlike those two, this is a **one-shot** surface — `show`
/// opens the panel with a fixed item list and returns immediately; the
/// eventual pick (or cancellation) arrives later as `onItemSelected` /
/// `onCancelled` on this same channel, entirely decoupled from the call that
/// opened it. There is no continuous state relay to build/tear down per
/// frame, which is why this host skips the retry/stall-recovery machinery
/// `FloatingOverlayHost` needs for its 30Hz relay — a picker is opened
/// rarely, and a slow boot only delays the panel's first appearance, not an
/// ongoing visual.
///
/// Seam:
/// - The main engine talks to this host over `com.whispaste.snippet_picker`
///   (`show` / `hide` / `destroy`, plus the `onItemSelected` / `onCancelled` /
///   `onRenderEngineDiagnostic` events it sends back).
/// - This host relays the item list to the picker engine over the private
///   `com.whispaste.snippet_picker_render` channel, and translates the picker
///   engine's `selectItem` / `cancel` calls back into the main-engine events.
///
/// The panel is created once and reused across pickers for the app session.
/// It is **not** created lazily on the first `show` (the original
/// `FloatingButtonHost` pattern): booting a second Flutter engine costs a
/// Dart isolate spawn plus theme/L10n resolution and a warm-up frame —
/// seconds in a debug/JIT build — and paying that inside the `show` handler
/// put the entire cost between the user's hotkey press and the panel
/// appearing. [prewarm] moves it to a few seconds after launch instead, off
/// the visible-startup path and long before the first press. `show` still
/// calls [ensurePanel], so a missed or failed prewarm degrades to the old
/// lazy behaviour rather than to no picker at all.
class SnippetPickerHost: NSObject, NSWindowDelegate {
  private static let logger = OSLog(subsystem: "com.whispaste.snippet_picker", category: "SnippetPickerHost")

  /// Fixed panel content size — the placeholder Dart UI doesn't yet report a
  /// measured size back, so this host picks a reasonable default. Revisit
  /// once the Fable design pass lands (ticket 06) if it needs to vary.
  private static let contentSize = NSSize(width: 360, height: 420)

  private var channel: FlutterMethodChannel

  private var panel: SnippetPickerPanel?
  private var renderEngine: FlutterEngine?
  private var renderViewController: FlutterViewController?
  private var renderChannel: FlutterMethodChannel?

  private var renderReady = false
  private var pendingItems: [[String: String]]?

  /// Start of the in-flight render-engine boot, so the `ready` handler can
  /// report how long the engine actually took to come up — the number that
  /// tells whether [prewarm] finished before the user's first hotkey press.
  private var renderBootStartedAt: DispatchTime?

  /// Guards [dismiss] against a re-entrant second call: `orderOut(nil)`
  /// resigns the panel's key status, which fires `windowDidResignKey` — that
  /// would otherwise call [dismiss] a second time (with `fireCancelled:
  /// true`) on top of an explicit `selectItem`/`hide` dismissal. AppKit does
  /// not guarantee the resign-key notification fires strictly after
  /// `isVisible` flips to false, so gating on `p.isVisible` alone isn't
  /// reliable — this latch is.
  private var isDismissing = false

  /// The app that was frontmost right before [show] activated WhisPaste, so
  /// [dismiss] can hand activation straight back to it.
  ///
  /// Load-bearing beyond politeness: `SnippetPickerPanel`'s whole
  /// `.nonactivatingPanel` design exists because
  /// `DesktopPasteHost.captureTarget()` *clears* the stored paste target
  /// whenever WhisPaste itself is frontmost. [show] now has to activate the
  /// app anyway (see [activateForKeyboard]), so the invariant can no longer
  /// be upheld *during* the picker — but it must be restored by the time the
  /// panel closes, or the **next** dictation trigger's `prime()` would run
  /// with WhisPaste still frontmost and capture nothing. The current pick is
  /// unaffected either way: the pipeline captures its target at key-down,
  /// long before `show`, and `SnippetPickerService` never re-primes.
  private var previousFrontApp: NSRunningApplication?

  /// How long after a [show] a lost key status still counts as the
  /// activation race rather than as the user dismissing the picker — see
  /// [windowDidResignKey].
  private static let keyReclaimWindow: DispatchTimeInterval = .milliseconds(500)

  private var keyReclaimDeadline: DispatchTime?
  private var didReclaimKeyThisShow = false

  /// Local `keyDown` monitor that guarantees Escape closes the picker (live-
  /// test bug: Escape did nothing while the search field had focus).
  ///
  /// Root-caused empirically: a Dart widget test pumping the picker's
  /// `SnippetPickerBody` directly proves the Dart-side wiring is already
  /// correct — `Shortcuts` maps Escape to `_CancelIntent` → `onCancel`, and
  /// it fires reliably there, on macOS's own `DefaultTextEditingShortcuts`
  /// map (escape only reads as "do nothing, don't propagate further" on
  /// Apple platforms — this widget's own `Shortcuts` sits nearer the focused
  /// leaf and wins first). So the gap isn't in the Dart layer; it's between
  /// the raw macOS keyDown and the Flutter engine — the exact mechanism
  /// inside the embedder (the search field's focus is held by the render
  /// engine's embedded text-input proxy view, and something in its
  /// `NSTextInputClient` handling doesn't keep forwarding Escape onward) was
  /// not confirmed further than that, since Enter already worked via a
  /// separate, independent path (`TextInputAction.done`) that doesn't go
  /// through the same code. A local event monitor makes the fix correct
  /// regardless of the exact mechanism, which is why this doesn't chase it
  /// further.
  ///
  /// A local event monitor sidesteps that entirely: it runs at
  /// `NSApplication`'s event-dispatch stage, strictly before `-sendEvent:`
  /// hands the key to whatever the current first responder is (Flutter's
  /// text-input proxy or otherwise), so it does not depend on anything the
  /// embedded engine does or doesn't do with the key afterwards. Scoped to
  /// "this picker's own panel is key" so it never touches the main window or
  /// any other panel, and consumes the event (returns `nil`) once handled so
  /// the swallowed keystroke can't *also* reach the search field.
  private var escapeMonitor: Any?

  /// Local `keyDown` monitor for Return/Enter — the exact same fix as
  /// [escapeMonitor], for the sibling regression it introduced.
  ///
  /// Enter used to reach the search field's `onSubmitted` via a path
  /// independent of the fragile `NSTextInputClient` forwarding that Escape
  /// needed a monitor for (see [escapeMonitor]'s doc) — that was true when
  /// this class doc was written, before [show]'s per-`show()`
  /// `contentViewController` detach/reattach (added later, see the comment
  /// there) started resetting the render view's `NSTextInputContext`
  /// session. `insertNewline:` — the `NSStandardKeyBindingResponding`
  /// selector AppKit's `interpretKeyEvents:` turns Return into for a
  /// text-input-active view, which Flutter's embedder translates into
  /// `TextInputAction.done`/`onSubmitted` — apparently rides the same
  /// `doCommandBySelector:` bridge as Escape's `cancelOperation:`, and
  /// degraded the same way once that session started getting reset on every
  /// re-show. Rather than forwarding a synthetic key event, this calls
  /// straight into the render engine's own submit logic (which needs to
  /// know the current search-filtered highlight, a Dart-only value) via a
  /// dedicated `submitHighlighted` render-channel message — see
  /// `SnippetPickerRenderChannel.onSubmit`.
  private var returnMonitor: Any?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.snippet_picker",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler(handle)
    installEscapeMonitor()
    installReturnMonitor()
  }

  /// Installed once for the host's lifetime — the closure re-checks
  /// `panel`/[panelOwnsKeyboard] on every keystroke, so it is a safe no-op
  /// long before [ensurePanel] ever creates a panel.
  private func installEscapeMonitor() {
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.panelOwnsKeyboard, event.keyCode == kVK_Escape else {
        return event
      }
      self.dismiss(fireCancelled: true, restoreFrontApp: true)
      return nil
    }
  }

  /// Whether a keystroke arriving in this process right now belongs to the
  /// picker.
  ///
  /// Deliberately gated on `isVisible` rather than on `isKeyWindow` (which
  /// both monitors used until the third live test). A **local** event monitor
  /// only ever sees events macOS already routed to *this process*, and macOS
  /// never routes keystrokes to an inactive app at all — so "the picker panel
  /// is on screen" is by itself enough to know the keystroke is meant for the
  /// picker, without also betting on the panel having won key status. That
  /// bet is exactly what turned out to be unreliable: `show`'s activation is
  /// asynchronous, and AppKit re-picks a key window when the app actually
  /// becomes active, so the panel can be visible and frontmost while
  /// `isKeyWindow` is still false — which silently disabled *both* monitors
  /// at the very moment they were needed.
  private var panelOwnsKeyboard: Bool {
    guard let p = panel else { return false }
    return p.isVisible && !isDismissing
  }

  /// Same lifetime/scoping rules as [installEscapeMonitor]; see
  /// [returnMonitor]'s doc for why this exists. Matches both the main Return
  /// key and the numpad Enter key.
  private func installReturnMonitor() {
    returnMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.panelOwnsKeyboard,
            event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter else {
        return event
      }
      self.renderChannel?.invokeMethod("submitHighlighted", arguments: nil)
      return nil
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      guard let args = call.arguments as? [String: Any],
            let items = args["items"] as? [[String: String]] else {
        result(nil)
        return
      }
      show(items: items)
      result(nil)

    case "hide":
      dismiss(fireCancelled: false, restoreFrontApp: true)
      result(nil)

    case "destroy":
      teardown()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Prewarm

  /// Boots the panel and its render engine ahead of the first `show`,
  /// without putting anything on screen. Called once from `AppDelegate`, a
  /// short while after launch.
  ///
  /// Invisible by construction: [ensurePanel] only allocates the panel and
  /// attaches the render `FlutterViewController`; the `orderFrontRegardless`
  /// / `makeKey` pair that puts the panel on screen exists solely in [show],
  /// and a freshly allocated `NSPanel` stays off-screen until it is ordered
  /// in. Nothing is drawn, no window becomes key, and — the property
  /// `SnippetPickerPanel` is built around — WhisPaste never becomes
  /// frontmost, so `DesktopPasteHost.captureTarget()`'s stored paste target
  /// is untouched.
  ///
  /// Deliberately not guarded against a second call: [ensurePanel] is
  /// idempotent *and* re-attempts a failed boot, so calling this after a
  /// failed attempt is a retry rather than a no-op.
  func prewarm() {
    let startedAt = DispatchTime.now()
    ensurePanel()
    os_log(
      "prewarm: boot dispatched, %{public}@ ms on the main thread (engine readiness is reported separately)",
      log: Self.logger, type: .info, Self.elapsedMillis(since: startedAt)
    )
  }

  /// Milliseconds elapsed since [start], preformatted as a string — this
  /// file's `os_log` calls interpolate `%{public}@` only, and there is no
  /// numeric-format precedent to follow.
  private static func elapsedMillis(since start: DispatchTime) -> String {
    let nanos = DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds
    return String(format: "%.0f", Double(nanos) / 1_000_000)
  }

  // MARK: - Show / dismiss

  /// Reads the cursor position natively (`NSEvent.mouseLocation`, AppKit's
  /// own bottom-left-origin space) rather than accepting x/y from Dart.
  ///
  /// An earlier version took the position from Dart's `ScreenRetriever`,
  /// which converts to a top-down y (`visibleHeight - mouseLocation.y`) for
  /// Flutter's own coordinate space — mixing that back into this AppKit-
  /// native positioning code silently mirrored the panel vertically
  /// whenever the cursor wasn't near vertical screen-center (where the two
  /// conventions happen to coincide, which is why a live test done there
  /// didn't catch it). Reading the cursor here avoids the cross-convention
  /// conversion entirely.
  private func show(items: [[String: String]]) {
    ensurePanel()
    guard let p = panel else { return }

    let cursor = NSEvent.mouseLocation
    // Anchor the panel's top-left at the cursor — it opens downward/rightward,
    // matching typical context-menu placement. Screen selection (for
    // clamping) uses the raw cursor point, not the already-offset origin —
    // picking the display the user is actually pointing at, not whichever
    // display the arithmetic happens to land the offset point on.
    let origin = clampToVisibleScreen(
      cursor: cursor,
      desiredOrigin: NSPoint(x: cursor.x, y: cursor.y - Self.contentSize.height),
      size: Self.contentSize
    )
    p.setFrameOrigin(origin)

    if renderReady {
      renderChannel?.invokeMethod("setItems", arguments: ["items": items])
    } else {
      pendingItems = items
    }

    // Remember the outgoing frontmost app before anything below can change
    // it — see [previousFrontApp] for why this is more than politeness.
    let front = NSWorkspace.shared.frontmostApplication
    previousFrontApp =
      front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front

    keyReclaimDeadline = DispatchTime.now() + Self.keyReclaimWindow
    didReclaimKeyThisShow = false

    // ORDER MATTERS from here down; the sequence is the fix for live-test 4
    // ("the app comes to the front but the arrow keys still do nothing").
    //
    // 1. On screen first. Everything after this — the appearance cycle, key
    //    status, activation — behaves differently for a window that AppKit
    //    considers off-screen, and an ordered-out `NSWindow` reports a `nil`
    //    `screen` and a non-`.visible` `occlusionState`.
    p.orderFrontRegardless()

    // 2. [prewarm] (190b7477) keeps the render engine — and its
    //    `FlutterViewController` — alive across the whole app session, so
    //    `bootRenderEngine` only ever attaches it to the panel once.
    //    Reordering the panel back on screen after a prior `orderOut` does
    //    not retrigger AppKit's normal appearance cycle for a view
    //    controller that was never detached, so the reused view keeps
    //    presenting whatever frame was last rasterized instead of the
    //    current Dart tree (confirmed live: the panel kept showing the
    //    empty-state frame from the very first boot even after the Dart side
    //    rebuilt with real items and even after further code changes to that
    //    empty-state widget itself). Detaching and reattaching the same view
    //    controller forces AppKit to redo that appearance cycle.
    //
    //    Moved to *after* `orderFrontRegardless` (was before it): Flutter's
    //    macOS view drives its frame production from a display link it sets
    //    up when the view moves to a window, keyed on that window's screen,
    //    and pauses it while the view is not on a visible window. Attaching
    //    while the panel was still off-screen therefore handed the engine a
    //    windowless/screenless view — the shape that produces exactly the
    //    "one stale frame, no further repaints" symptom this reattach was
    //    added to paper over. Attaching once the panel is genuinely on
    //    screen gives that setup a real screen to bind to. (The
    //    `occlusionVisible=` field logged below is the live check for this.)
    if let vc = renderViewController {
      p.contentViewController = nil
      p.contentViewController = vc
    }

    // 3. Claim key status and the first responder *before* activating, so
    //    that when the app does become active the panel is already the
    //    window AppKit finds in front — see [reassertKeyFocus] for why the
    //    old order (activate first) was a race, and [activateForKeyboard]
    //    for why activating at all is unavoidable.
    //
    //    Live-test bug this line originally fixed: the search field wasn't
    //    focused when the picker opened, so typing did nothing until the
    //    user clicked into it first. `bootRenderEngine` sets
    //    `p.contentViewController = vc`, which per AppKit makes `vc.view`
    //    the panel's `initialFirstResponder` — but that outlet applies only
    //    the FIRST time a window is ordered onto the screen, and this panel
    //    is reused for the whole app session (see the class doc). Setting
    //    the first responder explicitly, every time, removes the dependency
    //    on that one-shot semantics entirely.
    p.makeKey()
    let focused = p.makeFirstResponder(renderViewController?.view)

    // 4. Activate last.
    activateForKeyboard()

    logPanelState("show/sync", extra: "makeFirstResponder=\(focused)")
    DispatchQueue.main.async { [weak self] in self?.reassertKeyFocus() }
  }

  /// Makes WhisPaste the active app so the panel can actually receive
  /// keystrokes, while raising as little else as possible.
  ///
  /// Unavoidable, and the reason `SnippetPickerPanel`'s `.nonactivatingPanel`
  /// promise ("can become key WITHOUT activating the owning application")
  /// doesn't carry as far as its doc comment hoped: that mask governs which
  /// of *this app's* windows may hold key status, but macOS routes physical
  /// keystrokes to the **active application's** process in the first place.
  /// A panel of an inactive app is therefore keyboard-dead no matter what
  /// `makeKey()`/`makeFirstResponder()` report (confirmed live: opening the
  /// picker via the global hotkey left it keyboard-dead — no arrows, no
  /// typing, no Enter/Escape — while a mouse click still worked, because
  /// AppKit implicitly activates the clicked-on app as part of handling the
  /// click). Getting keyboard focus without activating at all would take a
  /// `CGEventTap`, i.e. a second Accessibility-permission channel and a
  /// hand-rolled key path into the engine — far past this feature's weight.
  ///
  /// What *is* avoidable is dragging the rest of the app on screen with it,
  /// which the previous `NSApp.activate(ignoringOtherApps:)` did (live-test
  /// 4: "it pulls the whole WhisPaste app to the front"): that API is
  /// documented as equivalent to `NSRunningApplication.activate` **with**
  /// `.activateAllWindows`, which raises every window the app owns — main
  /// window included. Omitting that option raises only the app's frontmost
  /// window, which step 3 above has just made be this panel.
  ///
  /// `.activateIgnoringOtherApps` is deprecated as of macOS 14 in favour of
  /// the cooperative `activate(options:)`, but is kept here on purpose (and
  /// emits no warning at this target's 10.15 deployment floor): the
  /// cooperative form may be *declined* for an app that isn't already
  /// active, and a declined activation degrades straight back to the
  /// keyboard-dead picker this whole method exists to prevent. The
  /// `appActive=` field logged on the next runloop turn is the live check.
  private func activateForKeyboard() {
    guard !NSApp.isActive else { return }
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
  }

  /// Re-claims key status and the first responder one runloop turn after
  /// [show], and logs the panel's real input state.
  ///
  /// App activation is not synchronous: `activate` posts a request, and the
  /// app becomes active on a later turn — at which point AppKit picks a key
  /// window of its own accord, and can hand key status to the main window
  /// (the app's remembered key window, and the only one here that may become
  /// *main* at all, since `SnippetPickerPanel.canBecomeMain` is false),
  /// silently undoing the `makeKey()` [show] performed while the app was
  /// still inactive. Re-asserting after the dust settles closes that race.
  ///
  /// Deliberately does **not** clobber a first responder that already lives
  /// inside the render view: once Dart requests focus for the search field,
  /// Flutter's embedded text-input proxy view — a descendant of the
  /// `FlutterViewController`'s view, not that view itself — becomes first
  /// responder, and stealing it back would break text input rather than fix
  /// focus.
  private func reassertKeyFocus() {
    guard let p = panel, p.isVisible else { return }
    if !NSApp.isActive {
      // The targeted activation was declined (see [activateForKeyboard]) —
      // fall back to the blunt form live-test 4 proved does activate this
      // app, accepting that it also raises the main window. Logged, so a
      // live report can tell "the panel-only activation worked" apart from
      // "it looked like it worked because this line never fired".
      NSApp.activate(ignoringOtherApps: true)
      logPanelState("show/next-runloop/activation-fallback")
    }
    if !p.isKeyWindow { p.makeKey() }
    if let renderView = renderViewController?.view {
      let responder = p.firstResponder as? NSView
      let alreadyInside = responder === renderView
        || (responder?.isDescendant(of: renderView) ?? false)
      if !alreadyInside { p.makeFirstResponder(renderView) }
    }
    logPanelState("show/next-runloop")
  }

  /// One-line snapshot of everything that decides whether a keystroke can
  /// reach the picker's Flutter engine, and whether that engine is allowed
  /// to paint. Preformatted into a single string because this file's
  /// `os_log` calls interpolate `%{public}@` only.
  ///
  /// Read live with:
  /// `log stream --predicate 'subsystem == "com.whispaste.snippet_picker"' --info`
  private func logPanelState(_ stage: String, extra: String = "") {
    guard let p = panel else { return }
    let responder = p.firstResponder.map { String(describing: type(of: $0)) } ?? "<nil>"
    let appKey = NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? "<nil>"
    let line = "\(stage): appActive=\(NSApp.isActive) panelKey=\(p.isKeyWindow) "
      + "panelVisible=\(p.isVisible) occlusionVisible=\(p.occlusionState.contains(.visible)) "
      + "firstResponder=\(responder) appKeyWindow=\(appKey)"
      + (extra.isEmpty ? "" : " \(extra)")
    os_log("%{public}@", log: Self.logger, type: .info, line)
  }

  /// Closes the panel and — unless [fireCancelled] is false (an explicit
  /// `hide()` from Dart, or a pick already in flight) — reports the
  /// dismissal to the main engine.
  ///
  /// Orders the panel out **before** invoking the callback so a snippet
  /// insert's native `typeText`/re-activation of the target app never races
  /// this panel's own teardown (see `SnippetPickerPanel`'s doc comment).
  ///
  /// [restoreFrontApp] hands activation back to whoever was frontmost before
  /// [show] activated WhisPaste (see [previousFrontApp]). Passed `true` for
  /// the deliberate close paths (Escape, Dart-side `cancel`, an explicit
  /// `hide`) and `false` for the two paths where something else is already
  /// deciding what comes forward: a pick — `DesktopPasteHost` activates the
  /// paste target itself moments later, and racing it would be worse than
  /// doing nothing — and `windowDidResignKey`, where the user just clicked
  /// some other app, which macOS is in the middle of activating.
  private func dismiss(fireCancelled: Bool, restoreFrontApp: Bool = false) {
    guard !isDismissing, let p = panel, p.isVisible else { return }
    isDismissing = true
    defer { isDismissing = false }
    keyReclaimDeadline = nil
    p.orderOut(nil)
    if restoreFrontApp { restorePreviousFrontApp() }
    if fireCancelled {
      channel.invokeMethod("onCancelled", arguments: nil)
    }
  }

  /// Yields activation back to [previousFrontApp], restoring the "WhisPaste
  /// is not frontmost" invariant the next dictation trigger's target capture
  /// depends on.
  ///
  /// Uses the cooperative activation on macOS 14+ (unlike
  /// [activateForKeyboard], which must not risk being declined): a *giving
  /// away* of focus by the currently active app is precisely the case macOS
  /// grants, and the same version split `DesktopPasteHost` already uses when
  /// it re-activates a paste target.
  private func restorePreviousFrontApp() {
    guard let previous = previousFrontApp else { return }
    previousFrontApp = nil
    guard !previous.isTerminated else { return }
    if #available(macOS 14.0, *) {
      previous.activate(options: [])
    } else {
      previous.activate(options: [.activateIgnoringOtherApps])
    }
  }

  // MARK: - Positioning

  /// Clamps [desiredOrigin] (top-left-anchored) so the panel stays fully
  /// within some connected screen's visible frame — same algorithm as
  /// `FloatingOverlayHost.clampToVisibleScreen`, but the target screen is
  /// picked from [cursor] itself rather than from [desiredOrigin]: the
  /// origin is already offset upward by the panel's height, so on a
  /// multi-display setup with screens of different heights, selecting by
  /// the offset point could pick the wrong (e.g. neighbouring) display.
  private func clampToVisibleScreen(cursor: NSPoint, desiredOrigin: NSPoint, size: NSSize) -> NSPoint {
    guard let target = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
      ?? nearestScreen(to: cursor) else {
      return desiredOrigin
    }

    let visible = target.visibleFrame
    let maxX = max(visible.minX, visible.maxX - size.width)
    let maxY = max(visible.minY, visible.maxY - size.height)
    let clampedX = min(max(desiredOrigin.x, visible.minX), maxX)
    let clampedY = min(max(desiredOrigin.y, visible.minY), maxY)
    return NSPoint(x: clampedX, y: clampedY)
  }

  private func nearestScreen(to point: NSPoint) -> NSScreen? {
    NSScreen.screens.min { distance(point, $0.frame) < distance(point, $1.frame) }
  }

  private func distance(_ point: NSPoint, _ rect: NSRect) -> CGFloat {
    let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
    let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
    return (dx * dx + dy * dy).squareRoot()
  }

  // MARK: - Panel + render-engine creation

  /// Idempotent: creates the panel if it doesn't exist yet, and boots the
  /// render engine unless a live one is already attached.
  ///
  /// The second half matters now that [prewarm] boots the engine before the
  /// user ever asks for a picker: a failed boot (`engine.run` returning
  /// false, so no view controller ever gets attached) used to be permanent,
  /// because the panel existed and this method returned early forever after.
  /// The picker would then stay blank for the whole app session. Keying the
  /// re-boot on `renderViewController` rather than on a separate failure flag
  /// keeps "is there a usable engine?" a single question with a single
  /// answer.
  private func ensurePanel() {
    if panel == nil {
      let p = SnippetPickerPanel(contentSize: Self.contentSize)
      p.delegate = self
      panel = p
      os_log("ensurePanel: panel created", log: Self.logger, type: .info)
    }
    if renderViewController == nil {
      bootRenderEngine()
    }
  }

  private func bootRenderEngine() {
    guard let p = panel else { return }
    renderReady = false

    // Discard the corpse of a failed earlier attempt (engine allocated, run
    // failed, no view controller) before allocating a fresh one, so a retry
    // can't leak a second engine.
    if renderEngine != nil, renderViewController == nil {
      renderEngine?.shutDownEngine()
      renderEngine = nil
    }

    renderBootStartedAt = DispatchTime.now()

    // macOS `runWithEntrypoint:` resolves the name only against the ROOT
    // library, so `snippetPickerMain` is declared in Dart's main.dart (it
    // delegates into the render app) — same constraint as the button/overlay
    // engines.
    let engine = FlutterEngine(name: "snippet_picker", project: nil)
    let didRun = engine.run(withEntrypoint: "snippetPickerMain")
    os_log("bootRenderEngine: engine.run(snippetPickerMain) -> %{public}@", log: Self.logger, type: .info, didRun ? "true" : "false")

    guard didRun else {
      renderEngine = engine
      return
    }

    let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    vc.backgroundColor = .clear

    let renderCh = FlutterMethodChannel(
      name: "com.whispaste.snippet_picker_render",
      binaryMessenger: engine.binaryMessenger
    )
    renderCh.setMethodCallHandler { [weak self] call, result in
      self?.handleRenderCall(call, result: result)
    }

    p.contentViewController = vc
    p.setContentSize(Self.contentSize)

    renderEngine = engine
    renderViewController = vc
    renderChannel = renderCh
  }

  // MARK: - Render-engine interactions (picker engine → native → main engine)

  private func handleRenderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      let bootMillis = renderBootStartedAt.map { Self.elapsedMillis(since: $0) } ?? "?"
      renderBootStartedAt = nil
      os_log(
        "render engine ready %{public}@ ms after boot start",
        log: Self.logger, type: .info, bootMillis
      )
      renderReady = true
      if let items = pendingItems {
        renderChannel?.invokeMethod("setItems", arguments: ["items": items])
        pendingItems = nil
      }
      result(nil)

    case "selectItem":
      guard let args = call.arguments as? [String: Any],
            let id = args["id"] as? String else {
        result(nil)
        return
      }
      dismiss(fireCancelled: false)
      channel.invokeMethod("onItemSelected", arguments: ["id": id])
      result(nil)

    case "cancel":
      dismiss(fireCancelled: true, restoreFrontApp: true)
      result(nil)

    case "reportError":
      if let args = call.arguments as? [String: Any], let message = args["message"] as? String {
        os_log("render engine reported an error: %{public}@", log: Self.logger, type: .error, message)
        channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": true])
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - NSWindowDelegate

  /// Clicking outside the panel resigns its key status — treat that the same
  /// as pressing Esc: close and report a cancellation.
  ///
  /// Except for the one resign that isn't a user action at all: when
  /// [activateForKeyboard]'s request lands, AppKit re-picks a key window for
  /// the now-active app and can hand key status to the main window — the
  /// app's remembered key window, and the only one of ours that may become
  /// *main* (`SnippetPickerPanel.canBecomeMain` is false). Until live-test 4
  /// that never surfaced here, because the panel never won key status in the
  /// first place; now that it does, an unguarded resign would slam the
  /// picker shut microseconds after the hotkey opened it. Reclaiming is
  /// bounded twice over — a short post-`show` window, and once per `show` —
  /// so a genuine click into another app is never mistaken for the race (the
  /// user cannot click anything within [keyReclaimWindow] of pressing the
  /// hotkey that opened the panel).
  func windowDidResignKey(_ notification: Notification) {
    logPanelState("windowDidResignKey")
    if let p = panel, p.isVisible, !didReclaimKeyThisShow,
       let deadline = keyReclaimDeadline, DispatchTime.now() < deadline {
      didReclaimKeyThisShow = true
      p.makeKey()
      logPanelState("windowDidResignKey/reclaimed")
      return
    }
    dismiss(fireCancelled: true)
  }

  /// Instrumentation only — pairs with the `show/sync` and
  /// `show/next-runloop` snapshots to show whether the panel ever really won
  /// key status, and when.
  func windowDidBecomeKey(_ notification: Notification) {
    logPanelState("windowDidBecomeKey")
  }

  /// Instrumentation only — the live check for the "the reused view is
  /// attached to a window macOS does not consider visible, so Flutter never
  /// presents another frame" half of the diagnosis (see the numbered comment
  /// in [show]).
  func windowDidChangeOcclusionState(_ notification: Notification) {
    logPanelState("windowDidChangeOcclusionState")
  }

  // MARK: - Teardown

  private func teardown() {
    if let monitor = escapeMonitor {
      NSEvent.removeMonitor(monitor)
      escapeMonitor = nil
    }
    if let monitor = returnMonitor {
      NSEvent.removeMonitor(monitor)
      returnMonitor = nil
    }
    previousFrontApp = nil
    renderChannel?.setMethodCallHandler(nil)
    panel?.delegate = nil
    panel?.close()
    panel = nil
    renderViewController = nil
    renderChannel = nil
    renderEngine?.shutDownEngine()
    renderEngine = nil
    renderReady = false
    renderBootStartedAt = nil
    pendingItems = nil
    channel.setMethodCallHandler(nil)
  }
}
