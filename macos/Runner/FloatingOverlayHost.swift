import Cocoa
import FlutterMacOS

/// MethodChannel host for the floating recording overlay on macOS.
///
/// ADR 0002 (Approach 1 / Variant B): the overlay window is a lifecycle-only
/// shell. It no longer draws — it hosts a dedicated **second Flutter engine**
/// (entrypoint `floatingOverlayMain`) inside a transparent, non-activating
/// `FloatingOverlayPanel` and forwards the main engine's render state to it.
///
/// Seam:
/// - The app's MAIN engine talks to this host over `com.whispaste.floating_overlay`
///   exactly as before (`updateSnapshot` / `setWaveformBars` /
///   `setPosition` / `setContextMenuItems`).
/// - This host relays the render payloads to the overlay engine over the
///   private `com.whispaste.floating_overlay_render` channel, and translates
///   the overlay engine's coarse interactions (`startDrag` / `bodyClicked` /
///   `showContextMenu`) back into the existing main-engine events
///   (`onDragEnded` / `onBodyClicked` / `onContextMenu`).
///
/// The panel is lazily created on the first `updateSnapshot` with
/// `visible: true` — matching the Windows C++ host behavior.
class FloatingOverlayHost {
  private var channel: FlutterMethodChannel
  private var panel: FloatingOverlayPanel?

  // Secondary Flutter engine that renders the shared FloatingOverlayView.
  private var renderEngine: FlutterEngine?
  private var renderViewController: FlutterViewController?
  private var renderChannel: FlutterMethodChannel?

  private var pendingPosition: NSPoint?
  private var pendingAnchorMode: String = "topCenter"
  // Overlay size class: "normal" | "compact" | "mini" (mirrors the Dart
  // OverlaySizeVariant serialised as snapshot["size"]).
  private var sizeClass: String = "normal"
  private var contextMenuItems: [(id: String, label: String)] = []
  private var screenObserver: NSObjectProtocol?

  // The render engine boots asynchronously: its Dart MethodChannel handler is
  // only ready a few runloop turns after `engine.run`. Until the engine sends
  // `ready`, relayed messages would be dropped — so we cache the latest render
  // state here and flush it the moment the engine announces itself.
  private var renderReady: Bool = false
  private var latestSnapshotArgs: [String: Any]?
  private var latestBars: [String: Any]?

  // Boot-race hardening: if `ready` never arrives (observed in the wild —
  // reproduced 2026-07-17, root cause not fully pinned down, but a fresh
  // engine instance reliably recovers it), a timeout tears down the stuck
  // engine and boots a fresh one rather than leaving the panel permanently
  // blank for the rest of the app session.
  private static let renderReadyTimeout: TimeInterval = 3.0
  private static let maxRenderReadyRetries = 2
  private var renderReadyTimeoutTimer: Timer?
  private var renderReadyRetryCount = 0

  // Runtime-stall hardening: the boot-race timer above only covers the
  // initial engine boot. But ANY later panel operation that touches AppKit
  // geometry/visibility (`setContentSize` in `resizePanelToContent()`,
  // `orderFront` when re-showing a hidden panel) synchronously waits on this
  // process's single OS main thread for Flutter's FlutterResizeSynchronizer
  // to commit a frame at the new size/visibility — the render engine's own
  // "merged UI and platform thread" model runs Dart UI work on that same
  // thread. Under raster-thread load (e.g. the waveform repainting at ~10Hz
  // during recording) that wait can outrun the synchronizer's own deadline;
  // observed in the wild as a native `Resize timed out` console line
  // immediately followed by the main engine's own `UiThreadWatchdog` jank
  // warning (both engines share the one OS main thread). When that happens
  // the CAMetalLayer can be left without a committed frame — the panel goes
  // silently blank even though `updateSnapshot`/`setWaveformBars` keep
  // flowing normally, because recording/transcription live entirely in the
  // main engine and never notice. There is no native callback for that
  // outcome, so `runPanelOperation` detects it symptomatically (the call
  // itself took abnormally long) and `recoverStuckPanel()` rebuilds the shell
  // — blackbox to the user, mirrors `bootRenderEngine`'s retry machinery.
  //
  // CONFIRMED 2026-07-29 from a live signed-release log (two independent
  // `resizePanelToContent` stalls, both immediately preceded by the bare
  // (non-NSLog) `Resize timed out` line that only Flutter's own
  // FlutterResizeSynchronizer emits): both stalls measured 1.00s–1.02s at
  // THIS call site, matching the synchronizer's own ~1s internal deadline.
  // So this is a bounded, self-returning synchronous stall, not an
  // indefinite hang — `runPanelOperation` cannot observe elapsed time faster
  // than the call itself returns, and a parallel `Timer`/`DispatchQueue`
  // watchdog would not help either: Timers scheduled on the main run loop
  // do not fire while that same thread is blocked inside a synchronous
  // AppKit/Flutter call, so nothing can "interrupt" this wait from the
  // outside. The only way to detect this stall faster is to make the
  // underlying resize not block for ~1s in the first place (Flutter engine
  // internals, out of scope for this file) — lowering
  // `panelOperationStallThreshold` further would not speed up detection of
  // *this* failure mode, only tighten the margin for a hypothetical
  // differently-shaped stall.
  //
  // Deliberately NOT added: a periodic forced-resize "heartbeat" to catch a
  // stuck CAMetalLayer between real operations. It was considered (see
  // task notes) but rejected — probing via the same `setContentSize` path
  // this comment describes would fire during the busiest raster window
  // (recording, ~10Hz waveform repaint) and could itself trigger the exact
  // ~1s stall it's meant to detect, on otherwise-healthy sessions. Each
  // false trigger then pays the full `recoverStuckPanel()` cost (engine
  // teardown + reboot), which is unverified to be cheap end-to-end — the
  // `ready` log below only confirms the platform-channel handshake, not
  // that a new frame has actually been composited on screen. Do not add
  // this without first confirming, from a live run, how long the gap is
  // between `recoverStuckPanel` completing and the next real
  // `onSnapshot`/paint — see the diagnosis notes for 2026-07-29.
  //
  // What DID change 2026-07-29: `panelRecoveryCooldown` dropped from 5.0s to
  // 1.5s. The prior 5s cooldown could itself block a second, genuinely
  // needed recovery attempt shortly after a first one — exactly the shape
  // of the "disappeared a second time" report that prompted this pass.
  private static let panelOperationStallThreshold: TimeInterval = 0.5
  private static let maxPanelRecoveryRetries = 3
  private static let panelRecoveryCooldown: TimeInterval = 1.5
  private var panelRecoveryRetryCount = 0
  private var lastPanelRecoveryAt: Date?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.floating_overlay",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
    observeScreenChanges()
  }

  /// Observes monitor connect/disconnect events and repositions the overlay
  /// so it stays on-screen — matching the Windows WM_DISPLAYCHANGE behavior.
  private func observeScreenChanges() {
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.validateOnScreen()
    }
  }

  /// Recalculates the overlay position for the current screen geometry.
  private func validateOnScreen() {
    guard let p = panel, p.isVisible else { return }
    let origin = p.frame.origin
    let resolved = resolvePosition(x: Double(origin.x), y: Double(origin.y), anchorMode: pendingAnchorMode)
    if resolved != origin {
      p.setFrameOrigin(resolved)
      channel.invokeMethod("onDragEnded", arguments: [
        "x": Double(resolved.x),
        "y": Double(resolved.y),
        "anchorMode": pendingAnchorMode,
      ])
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateSnapshot":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      handleUpdateSnapshot(args)
      result(nil)

    case "setWaveformBars":
      // Relay the pre-computed bar array straight to the render engine; the
      // shell keeps no waveform state of its own.
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      latestBars = args
      if renderReady {
        renderChannel?.invokeMethod("setWaveformBars", arguments: args)
      }
      result(nil)

    case "setPosition":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      let x = (args["x"] as? NSNumber)?.doubleValue ?? 0
      let y = (args["y"] as? NSNumber)?.doubleValue ?? 0
      let anchorMode = args["anchorMode"] as? String ?? "topLeft"
      pendingAnchorMode = anchorMode
      let resolved = resolvePosition(x: x, y: y, anchorMode: anchorMode)
      if let p = panel {
        p.setFrameOrigin(resolved)
      } else {
        pendingPosition = resolved
      }
      result(nil)

    case "setContextMenuItems":
      guard let args = call.arguments as? [String: Any],
            let items = args["items"] as? [[String: Any]] else {
        result(nil)
        return
      }
      contextMenuItems = items.compactMap { item in
        guard let id = item["id"] as? String,
              let label = item["label"] as? String else { return nil }
        return (id: id, label: label)
      }
      result(nil)

    case "destroy":
      teardown()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - updateSnapshot (lazy-creates panel + engine, handles show/hide)

  private func handleUpdateSnapshot(_ args: [String: Any]) {
    let visible = args["visible"] as? Bool ?? false
    // "size" is the canonical key; fall back to the legacy "compact" bool for
    // payloads from an older main engine.
    let size = args["size"] as? String
      ?? ((args["compact"] as? Bool ?? false) ? "compact" : "normal")
    let sizeChanged = size != sizeClass
    // Set the size class BEFORE lazy-creating the panel so the very first
    // (possibly compact/mini) snapshot sizes the shell correctly instead of
    // creating it at normal size and resizing a frame later.
    sizeClass = size

    if visible && panel == nil {
      ensurePanel()
    } else if sizeChanged {
      // Re-size + re-anchor the existing shell on a size-class switch. This
      // synchronously touches AppKit/Flutter geometry — see
      // `panelOperationStallThreshold` doc — so it goes through the watchdog.
      runPanelOperation("resizePanelToContent") { [weak self] in
        self?.resizePanelToContent()
      }
    }

    // Cache + relay (relay no-ops until the engine is ready; flushed on ready).
    latestSnapshotArgs = args
    if renderReady {
      renderChannel?.invokeMethod("updateSnapshot", arguments: args)
    }

    // Show or hide the native shell. Re-showing a previously-hidden panel is
    // the other synchronous, potentially-blocking AppKit/Flutter operation
    // (see `panelOperationStallThreshold`), so it also goes through the
    // watchdog. `orderOut` is not — hiding never waits on a fresh committed
    // frame, so it isn't a wedge risk.
    if visible {
      runPanelOperation("orderFront") { [weak self] in
        self?.panel?.orderFront(nil)
      }
    } else {
      panel?.orderOut(nil)
    }
  }

  /// Runs `op` — a synchronous panel geometry/visibility mutation that may
  /// block the shared OS main thread on Flutter's resize synchronizer (see
  /// `panelOperationStallThreshold` doc above) — and treats an abnormally
  /// long call as a signal the shell may be wedged, triggering a silent
  /// rebuild via `recoverStuckPanel()`.
  ///
  /// CONFIRMED 2026-07-29: this Swift-level call IS where the wall-clock
  /// time goes. A live signed-release log captured two `resizePanelToContent`
  /// calls each measuring 1.00s–1.02s right here, both immediately preceded
  /// by the engine's own un-prefixed `Resize timed out` line. Every
  /// invocation still logs its elapsed time unconditionally (not just on
  /// threshold-breach) — keep it that way, it is the only signal that made
  /// this diagnosis possible and the next live repro will need it again to
  /// answer the still-open question of how long the gap is between this
  /// function returning and the panel actually being visible again.
  private func runPanelOperation(_ label: String, _ op: () -> Void) {
    let start = CFAbsoluteTimeGetCurrent()
    op()
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    NSLog(
      "[overlay] panel operation '\(label)' took \(String(format: "%.3f", elapsed))s, panel.isVisible=\(panel?.isVisible ?? false), frame=\(panel?.frame ?? .zero)"
    )
    guard elapsed > Self.panelOperationStallThreshold else { return }

    let message =
      "panel operation '\(label)' took \(String(format: "%.2f", elapsed))s (> \(Self.panelOperationStallThreshold)s) — rebuilding overlay shell as a precaution"
    NSLog("[overlay] \(message)")
    channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": false])
    recoverStuckPanel()
  }

  /// Blackbox recovery for a suspected-wedged shell: tears down the panel
  /// AND the render engine and rebuilds both from scratch, then immediately
  /// re-applies the last known position/visibility/snapshot/waveform state
  /// (the existing `ready`-handler flush already does the snapshot/bars
  /// replay — see `handleRenderCall`'s `"ready"` case). Recording/
  /// transcription live entirely in the MAIN engine and never touch this
  /// path, so they are unaffected. Bounded + cooldown-gated (mirrors
  /// `handleRenderReadyTimeout`) so a genuinely overloaded machine can't
  /// loop-rebuild forever.
  private func recoverStuckPanel() {
    let now = Date()
    if let last = lastPanelRecoveryAt, now.timeIntervalSince(last) < Self.panelRecoveryCooldown {
      NSLog("[overlay] recoverStuckPanel: skipped — still within cooldown window")
      return
    }
    guard panelRecoveryRetryCount < Self.maxPanelRecoveryRetries else {
      NSLog("[overlay] recoverStuckPanel: retry budget exhausted — leaving shell as-is")
      return
    }
    panelRecoveryRetryCount += 1
    lastPanelRecoveryAt = now

    let wasVisible = panel?.isVisible ?? false
    let origin = panel?.frame.origin
    let size = contentSize()

    renderReadyTimeoutTimer?.invalidate()
    renderReadyTimeoutTimer = nil
    renderChannel?.setMethodCallHandler(nil)
    renderEngine?.shutDownEngine()
    renderEngine = nil
    renderViewController = nil
    renderChannel = nil
    renderReady = false
    panel?.close()
    panel = nil

    let p = FloatingOverlayPanel(width: size.width, height: size.height)
    panel = p
    if let origin {
      p.setFrameOrigin(origin)
    }
    bootRenderEngine()
    if wasVisible {
      p.orderFront(nil)
    }
    NSLog("[overlay] recoverStuckPanel: shell rebuilt (attempt \(panelRecoveryRetryCount)/\(Self.maxPanelRecoveryRetries))")
  }

  // MARK: - Panel + render-engine creation

  /// Full native-window size = pill box + 8pt shadow padding per side.
  /// Mirrors `OverlayDesignSpec.windowSizeFor` (Dart). Normal `346 × 80`,
  /// compact `236 × 56`, mini `166 × 50`. The shell MUST match this so the
  /// painted soft shadow is not clipped.
  private func contentSize() -> NSSize {
    switch sizeClass {
    case "compact":
      return NSSize(width: 236, height: 56)
    case "mini":
      return NSSize(width: 166, height: 50)
    default:
      return NSSize(width: 346, height: 80)
    }
  }

  private func ensurePanel() {
    let size = contentSize()

    let p = FloatingOverlayPanel(width: size.width, height: size.height)
    panel = p
    bootRenderEngine()
    NSLog("[overlay] ensurePanel: panel created, content \(size.width)x\(size.height)")

    // Apply pending position if one was set before the panel existed.
    if let pos = pendingPosition {
      p.setFrameOrigin(pos)
      pendingPosition = nil
    }
  }

  /// Creates a fresh render-engine instance and hosts it in the existing
  /// panel. Split out from `ensurePanel()` so a stuck boot (see
  /// `renderReadyTimeoutTimer`) can retry with a brand-new `FlutterEngine`
  /// without tearing down/recreating the native panel itself (position,
  /// size, and screen-observer wiring all stay put).
  private func bootRenderEngine() {
    guard let p = panel else { return }
    renderReady = false
    renderReadyTimeoutTimer?.invalidate()

    // Boot the dedicated overlay engine and host its view in the panel.
    // macOS `runWithEntrypoint:` resolves the name only against the ROOT
    // library, so `floatingOverlayMain` is declared in Dart's main.dart (it
    // delegates into the overlay render app). There is no `libraryURI:`
    // variant on macOS FlutterEngine.
    let engine = FlutterEngine(name: "floating_overlay", project: nil)
    let didRun = engine.run(withEntrypoint: "floatingOverlayMain")
    NSLog("[overlay] bootRenderEngine: engine.run(floatingOverlayMain) -> \(didRun)")

    guard didRun else {
      // Engine failed to start outright — no point waiting out the full
      // timeout window before retrying.
      renderEngine = engine
      handleRenderReadyTimeout()
      return
    }

    let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    // REAL surface transparency: must be set so the engine composites onto a
    // clear surface instead of opaque black. Set before the view is shown.
    vc.backgroundColor = .clear

    let renderCh = FlutterMethodChannel(
      name: "com.whispaste.floating_overlay_render",
      binaryMessenger: engine.binaryMessenger
    )
    renderCh.setMethodCallHandler { [weak self] call, result in
      self?.handleRenderCall(call, result: result)
    }

    // ⚠️ DO NOT replace `contentViewController` with a manual container/subview
    // setup (e.g. to slip an NSVisualEffectView behind the Flutter surface for
    // "frosted glass"). Hosting the FlutterViewController's view as a plain
    // subview instead of as the panel's `contentViewController` breaks the
    // Flutter view's sizing / backing-scale on this NSPanel → the overlay
    // renders grossly oversized and clipped. Reproduced TWICE (2026-06-30) and
    // reverted both times.
    //
    // NOTE (2026-06-30, task #38): a proper view-controller-CONTAINMENT spike
    // (Flutter VC added as a child VC behind a pill-masked NSVisualEffectView)
    // DID keep sizing correct and produced real desktop blur — but the chosen
    // "frosted glass" is the cross-platform faux-glass painted in Dart
    // (OverlayPainter, identical on macOS/Windows/Linux), so no native blur is
    // wired here. The panel stays a clear shell. See ADR 0002.
    p.contentViewController = vc
    p.setContentSize(contentSize())

    renderEngine = engine
    renderViewController = vc
    renderChannel = renderCh

    // Boot-race hardening: if `ready` doesn't arrive in time, tear this
    // engine down and try a fresh one (bounded retries) instead of leaving
    // the panel silently blank for the rest of the session.
    let timer = Timer.scheduledTimer(withTimeInterval: Self.renderReadyTimeout, repeats: false) { [weak self] _ in
      self?.handleRenderReadyTimeout()
    }
    renderReadyTimeoutTimer = timer
  }

  private func handleRenderReadyTimeout() {
    guard !renderReady else { return }

    if renderReadyRetryCount < Self.maxRenderReadyRetries {
      renderReadyRetryCount += 1
      let message =
        "render engine did not signal ready within \(Self.renderReadyTimeout)s — retrying (attempt \(renderReadyRetryCount)/\(Self.maxRenderReadyRetries))"
      NSLog("[overlay] \(message)")
      channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": false])
      renderEngine?.shutDownEngine()
      bootRenderEngine()
    } else {
      let message =
        "render engine never signaled ready after \(Self.maxRenderReadyRetries) retries — overlay content will stay blank until the app restarts"
      NSLog("[overlay] \(message)")
      channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": true])
      // Don't keep a permanently-stuck engine's thread/GPU resources alive
      // for the rest of the session — it will never become useful.
      renderEngine?.shutDownEngine()
      renderEngine = nil
    }
  }

  private func resizePanelToContent() {
    guard let p = panel else { return }
    let origin = p.frame.origin
    p.setContentSize(contentSize())
    // Re-anchor: a top/bottom-centre overlay must stay centred after the size
    // changes; a dragged (topLeft) overlay keeps its raw origin.
    let resolved = resolvePosition(
      x: Double(origin.x), y: Double(origin.y), anchorMode: pendingAnchorMode)
    p.setFrameOrigin(resolved)
  }

  // MARK: - Render-engine interactions (overlay engine → native → main engine)

  private func handleRenderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      // The render engine's Dart handler is live — flush the cached state so
      // the first visible frame is never lost to the boot race.
      NSLog("[overlay] render engine ready — flushing cached state")
      renderReadyTimeoutTimer?.invalidate()
      renderReadyTimeoutTimer = nil
      renderReadyRetryCount = 0
      // A clean ready-signal means the shell is healthy again — let future
      // genuine stalls get the full retry budget rather than staying
      // permanently exhausted after one bad patch of jank earlier in a long
      // session.
      panelRecoveryRetryCount = 0
      renderReady = true
      if let bars = latestBars {
        renderChannel?.invokeMethod("setWaveformBars", arguments: bars)
      }
      if let snap = latestSnapshotArgs {
        renderChannel?.invokeMethod("updateSnapshot", arguments: snap)
      }
      result(nil)

    case "startDrag":
      if let event = NSApp.currentEvent, let p = panel {
        p.performDrag(with: event)
        // The drag loop has ended — persist the final origin via the existing
        // main-engine event (topLeft = raw coordinates).
        let origin = p.frame.origin
        pendingAnchorMode = "topLeft"
        channel.invokeMethod("onDragEnded", arguments: [
          "x": Double(origin.x),
          "y": Double(origin.y),
          "anchorMode": "topLeft",
        ])
      }
      result(nil)

    case "bodyClicked":
      channel.invokeMethod("onBodyClicked", arguments: nil)
      result(nil)

    case "showContextMenu":
      showContextMenu()
      result(nil)

    case "reportError":
      // Uncaught Dart error inside the render engine (see
      // `shared_render_engine_helpers.dart`'s `RenderChannel.reportError`
      // doc comment for why this matters) — relay it through the existing
      // diagnostic pipeline into the main engine's persistent AppLogger,
      // exactly like the boot-race timeout below.
      if let args = call.arguments as? [String: Any], let message = args["message"] as? String {
        NSLog("[overlay] render engine reported an error: \(message)")
        channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": true])
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func showContextMenu() {
    guard !contextMenuItems.isEmpty else { return }
    let menu = NSMenu()
    for item in contextMenuItems {
      let menuItem = NSMenuItem(
        title: item.label,
        action: #selector(contextMenuItemSelected(_:)),
        keyEquivalent: ""
      )
      menuItem.target = self
      menuItem.representedObject = item.id
      menu.addItem(menuItem)
    }
    if let event = NSApp.currentEvent, let view = renderViewController?.view {
      NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
  }

  @objc private func contextMenuItemSelected(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    channel.invokeMethod("onContextMenu", arguments: ["action": id])
  }

  // MARK: - Teardown

  private func teardown() {
    if let obs = screenObserver {
      NotificationCenter.default.removeObserver(obs)
      screenObserver = nil
    }
    renderReadyTimeoutTimer?.invalidate()
    renderReadyTimeoutTimer = nil
    renderReadyRetryCount = 0
    renderChannel?.setMethodCallHandler(nil)
    panel?.close()
    panel = nil
    renderViewController = nil
    renderChannel = nil
    renderEngine?.shutDownEngine()
    renderEngine = nil
    renderReady = false
    latestSnapshotArgs = nil
    latestBars = nil
    channel.setMethodCallHandler(nil)
  }

  // MARK: - Position resolution (anchor mode → screen coordinates)

  /// Compute the frame origin for the overlay based on anchor mode.
  ///
  /// Mirrors the Windows `ResolveAnchorPosition()` / Linux `ResolvePosition()`
  /// logic:
  /// - topCenter: centered horizontally, 16pt from top of visible frame
  /// - bottomCenter: centered horizontally, 16pt from bottom of visible frame
  /// - topLeft: use raw x/y as frame origin
  private func resolvePosition(x: Double, y: Double, anchorMode: String) -> NSPoint {
    // Anchor to the primary display, not `NSScreen.main` (the screen holding
    // the *key window of the frontmost app*, which drifts to whatever the
    // user is focused on and isn't necessarily WhisPaste's own window or
    // display). `.screens.first` is always the primary display — this is the
    // documented ADR 0002 multi-monitor rule ("NSScreen.screens.first
    // (Primärdisplay), nicht NSScreen.main") and matches Windows/Linux, which
    // both anchor topCenter/bottomCenter to the primary monitor.
    guard let screen = NSScreen.screens.first else {
      return NSPoint(x: x, y: y)
    }

    let visibleFrame = screen.visibleFrame
    let size = contentSize()
    let margin: CGFloat = 16

    switch anchorMode {
    case "topCenter":
      // NSView Y-up: "top" means near maxY of visible frame.
      let px = visibleFrame.origin.x + (visibleFrame.width - size.width) / 2
      let py = visibleFrame.maxY - size.height - margin
      return NSPoint(x: px, y: py)

    case "bottomCenter":
      // NSView Y-up: "bottom" means near minY of visible frame.
      let px = visibleFrame.origin.x + (visibleFrame.width - size.width) / 2
      let py = visibleFrame.origin.y + margin
      return NSPoint(x: px, y: py)

    default: // "topLeft" — raw coordinates, clamped to stay on-screen
      return clampToVisibleScreen(x: x, y: y, size: size)
    }
  }

  /// Clamps a topLeft-anchored origin so the panel stays fully within some
  /// connected screen's visible frame — mirrors the Windows
  /// `FloatingOverlayWindow::ValidatePosition()` clamp. Picks the screen whose
  /// frame contains the point, falling back to the nearest screen by distance
  /// (e.g. after the monitor the overlay was dragged to gets unplugged and
  /// the stored point is no longer on any connected display). Closes the gap
  /// where `validateOnScreen()` recalculated topCenter/bottomCenter overlays
  /// on a screen-parameters change but left a dragged (topLeft) overlay's raw
  /// coordinates untouched.
  private func clampToVisibleScreen(x: Double, y: Double, size: NSSize) -> NSPoint {
    let point = NSPoint(x: x, y: y)
    guard let target = NSScreen.screens.first(where: { $0.frame.contains(point) })
      ?? nearestScreen(to: point) else {
      return point
    }

    let visible = target.visibleFrame
    let maxX = max(visible.minX, visible.maxX - size.width)
    let maxY = max(visible.minY, visible.maxY - size.height)
    let clampedX = min(max(x, visible.minX), maxX)
    let clampedY = min(max(y, visible.minY), maxY)
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
}
