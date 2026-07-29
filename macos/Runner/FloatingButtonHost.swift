import Cocoa
import FlutterMacOS

/// MethodChannel host for the floating button on macOS.
///
/// ADR 0002 (Approach 1 / Variant B): the button window is a lifecycle-only
/// shell. It no longer draws — it hosts a dedicated **second Flutter engine**
/// (entrypoint `floatingButtonMain`) inside a transparent, non-activating
/// `FloatingButtonPanel` and forwards the main engine's render state to it.
///
/// Seam:
/// - The app's MAIN engine talks to this host over `com.whispaste.floating_button`
///   exactly as before (`show` / `hide` / `setState` / `setTheme` / `setPosition` /
///   `setSize` / `getPosition` / `setContextMenuItems` / `destroy`).
/// - This host relays the render payloads to the button engine over the
///   private `com.whispaste.floating_button_render` channel, and translates
///   the button engine's interactions (`clicked` / `startDrag` /
///   `showContextMenu`) back into the existing main-engine events
///   (`onClicked` / `onDragEnded` / `onContextMenu` / `onSecondaryClicked`).
///
/// The panel is lazily created on the first `show` — matching the old host
/// behaviour and the Windows C++ host.
class FloatingButtonHost {
  private var channel: FlutterMethodChannel

  // Lazy-created on first show.
  private var panel: FloatingButtonPanel?

  // Secondary Flutter engine that renders the shared FloatingButtonView.
  private var renderEngine: FlutterEngine?
  private var renderViewController: FlutterViewController?
  private var renderChannel: FlutterMethodChannel?

  private var contextMenuItems: [(id: String, label: String)] = []
  private var screenObserver: NSObjectProtocol?

  // The render engine boots asynchronously: its Dart MethodChannel handler is
  // only ready a few runloop turns after `engine.run`. Until the engine sends
  // `ready`, relayed messages would be dropped — so we cache the latest render
  // state here and flush it the moment the engine announces itself.
  private var renderReady: Bool = false
  private var latestState: String?
  private var latestDiameter: Double = 56

  // Boot-race hardening: if `ready` never arrives (same class of race as
  // FloatingOverlayHost's — see its comment), a timeout tears down the stuck
  // engine and boots a fresh one rather than leaving the button permanently
  // blank for the rest of the app session.
  private static let renderReadyTimeout: TimeInterval = 3.0
  private static let maxRenderReadyRetries = 2
  private var renderReadyTimeoutTimer: Timer?
  private var renderReadyRetryCount = 0

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.floating_button",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
    observeScreenChanges()
  }

  /// Observes monitor connect/disconnect events and repositions the button
  /// so it stays on-screen — matching the Windows WM_DISPLAYCHANGE behavior.
  private func observeScreenChanges() {
    screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.validatePosition()
    }
  }

  /// Clamps the button position to the current visible screen area.
  private func validatePosition() {
    guard let p = panel, p.isVisible else { return }
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let visibleFrame = screen.visibleFrame
    var origin = p.frame.origin
    let size = p.frame.size

    // Clamp horizontal
    if origin.x + size.width < visibleFrame.minX + 10 {
      origin.x = visibleFrame.minX
    } else if origin.x > visibleFrame.maxX - 10 {
      origin.x = visibleFrame.maxX - size.width
    }

    // Clamp vertical
    if origin.y + size.height < visibleFrame.minY + 10 {
      origin.y = visibleFrame.minY
    } else if origin.y > visibleFrame.maxY - 10 {
      origin.y = visibleFrame.maxY - size.height
    }

    if origin != p.frame.origin {
      p.setFrameOrigin(origin)
      let adjusted = p.frame.origin
      channel.invokeMethod("onDragEnded", arguments: [
        "x": Double(adjusted.x),
        "y": Double(adjusted.y),
      ])
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      let x = (args["x"] as? NSNumber)?.doubleValue ?? 200
      let y = (args["y"] as? NSNumber)?.doubleValue ?? 200
      let size = (args["size"] as? NSNumber)?.doubleValue ?? 56
      show(x: x, y: y, size: size)
      result(nil)

    case "hide":
      panel?.orderOut(nil)
      result(nil)

    case "setState":
      guard let args = call.arguments as? [String: Any],
            let stateName = args["state"] as? String else {
        result(nil)
        return
      }
      latestState = stateName
      // [DEBUG-a1] hypothesis 3: is a setState relay ever dropped because
      // renderReady is false (boot-race / stuck-engine window)?
      NSLog("[button][DEBUG-a1] setState(\(stateName)) renderReady=\(renderReady) renderChannel=\(renderChannel != nil)")
      if renderReady {
        renderChannel?.invokeMethod("setState", arguments: ["state": stateName])
      }
      result(nil)

    case "setTheme":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      // Relay to render engine (V2 disc is theme-independent, render ignores).
      if renderReady {
        renderChannel?.invokeMethod("setTheme", arguments: args)
      }
      result(nil)

    case "setPosition":
      guard let args = call.arguments as? [String: Any] else {
        result(nil)
        return
      }
      let x = (args["x"] as? NSNumber)?.doubleValue ?? 0
      let y = (args["y"] as? NSNumber)?.doubleValue ?? 0
      panel?.setFrameOrigin(NSPoint(x: x, y: y))
      result(nil)

    case "setSize":
      guard let args = call.arguments as? [String: Any],
            let size = (args["size"] as? NSNumber)?.doubleValue else {
        result(nil)
        return
      }
      latestDiameter = size
      let totalSize = size + 16 // OverlayDesignSpec.shadowPadding (8) * 2
      if let p = panel {
        var frame = p.frame
        frame.size = NSSize(width: totalSize, height: totalSize)
        p.setFrame(frame, display: true)
      }
      if renderReady {
        renderChannel?.invokeMethod("setDiameter", arguments: ["diameter": size])
      }
      result(nil)

    case "getPosition":
      guard let p = panel else {
        result(nil)
        return
      }
      let origin = p.frame.origin
      result(["x": Double(origin.x), "y": Double(origin.y)])

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

  // MARK: - Panel + render-engine creation

  private func ensurePanel(totalSize: Double) {
    guard panel == nil else { return }
    let p = FloatingButtonPanel(size: CGFloat(totalSize))
    panel = p
    bootRenderEngine(totalSize: totalSize)
    NSLog("[button] ensurePanel: panel created \(totalSize)x\(totalSize)")
  }

  /// Creates a fresh render-engine instance and hosts it in the existing
  /// panel. Split out from `ensurePanel()` so a stuck boot (see
  /// `renderReadyTimeoutTimer`) can retry with a brand-new `FlutterEngine`
  /// without recreating the native panel itself.
  private func bootRenderEngine(totalSize: Double) {
    guard let p = panel else { return }
    renderReady = false
    renderReadyTimeoutTimer?.invalidate()

    // Boot the dedicated button engine and host its view in the panel.
    // macOS `runWithEntrypoint:` resolves the name only against the ROOT
    // library, so `floatingButtonMain` is declared in Dart's main.dart (it
    // delegates into the button render app). There is no `libraryURI:` variant
    // on macOS FlutterEngine.
    let engine = FlutterEngine(name: "floating_button", project: nil)
    let didRun = engine.run(withEntrypoint: "floatingButtonMain")
    NSLog("[button] bootRenderEngine: engine.run(floatingButtonMain) -> \(didRun)")

    guard didRun else {
      // Engine failed to start outright — no point waiting out the full
      // timeout window before retrying.
      renderEngine = engine
      handleRenderReadyTimeout(totalSize: totalSize)
      return
    }

    let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    // REAL surface transparency: must be set so the engine composites onto a
    // clear surface instead of opaque black. Set before the view is shown.
    vc.backgroundColor = .clear

    let renderCh = FlutterMethodChannel(
      name: "com.whispaste.floating_button_render",
      binaryMessenger: engine.binaryMessenger
    )
    renderCh.setMethodCallHandler { [weak self] call, result in
      self?.handleRenderCall(call, result: result)
    }

    p.contentViewController = vc
    p.setContentSize(NSSize(width: totalSize, height: totalSize))

    renderEngine = engine
    renderViewController = vc
    renderChannel = renderCh

    // Boot-race hardening: if `ready` doesn't arrive in time, tear this
    // engine down and try a fresh one (bounded retries) instead of leaving
    // the button silently blank for the rest of the session.
    let timer = Timer.scheduledTimer(withTimeInterval: Self.renderReadyTimeout, repeats: false) { [weak self] _ in
      self?.handleRenderReadyTimeout(totalSize: totalSize)
    }
    renderReadyTimeoutTimer = timer
  }

  private func handleRenderReadyTimeout(totalSize: Double) {
    guard !renderReady else { return }

    if renderReadyRetryCount < Self.maxRenderReadyRetries {
      renderReadyRetryCount += 1
      let message =
        "render engine did not signal ready within \(Self.renderReadyTimeout)s — retrying (attempt \(renderReadyRetryCount)/\(Self.maxRenderReadyRetries))"
      NSLog("[button] \(message)")
      channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": false])
      renderEngine?.shutDownEngine()
      bootRenderEngine(totalSize: totalSize)
    } else {
      let message =
        "render engine never signaled ready after \(Self.maxRenderReadyRetries) retries — button content will stay blank until the app restarts"
      NSLog("[button] \(message)")
      channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": true])
      // Don't keep a permanently-stuck engine's thread/GPU resources alive
      // for the rest of the session — it will never become useful.
      renderEngine?.shutDownEngine()
      renderEngine = nil
    }
  }

  private func show(x: Double, y: Double, size: Double) {
    // Total window size = disc + shadowPadding on every side.
    // OverlayDesignSpec.shadowPadding = 8  →  totalSize = size + 16
    let totalSize = size + 16
    latestDiameter = size

    ensurePanel(totalSize: totalSize)

    // If size changed after the panel was already created, resize it.
    if let p = panel {
      let newSize = NSSize(width: totalSize, height: totalSize)
      if p.frame.size != newSize {
        var frame = p.frame
        frame.size = newSize
        p.setFrame(frame, display: true)
        if renderReady {
          renderChannel?.invokeMethod("setDiameter", arguments: ["diameter": size])
        }
      }
    }

    // Offset the panel origin so the logical position (x, y) aligns with the
    // disc center: (totalSize - size) / 2 == shadowPadding == 8.
    let shadowPadding = (totalSize - size) / 2
    panel?.setFrameOrigin(NSPoint(x: x - shadowPadding, y: y - shadowPadding))
    panel?.orderFront(nil)
  }

  // MARK: - Render-engine interactions (button engine → native → main engine)

  private func handleRenderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      // The render engine's Dart handler is live — flush the cached state so
      // the first visible frame is never lost to the boot race.
      NSLog("[button] render engine ready — flushing cached state")
      renderReadyTimeoutTimer?.invalidate()
      renderReadyTimeoutTimer = nil
      renderReadyRetryCount = 0
      renderReady = true
      if let state = latestState {
        renderChannel?.invokeMethod("setState", arguments: ["state": state])
      }
      renderChannel?.invokeMethod("setDiameter", arguments: ["diameter": latestDiameter])
      result(nil)

    case "startDrag":
      if let event = NSApp.currentEvent, let p = panel {
        p.performDrag(with: event)
        // The drag loop has ended — persist the final origin via the existing
        // main-engine event.
        let origin = p.frame.origin
        channel.invokeMethod("onDragEnded", arguments: [
          "x": Double(origin.x),
          "y": Double(origin.y),
        ])
      }
      result(nil)

    case "clicked":
      channel.invokeMethod("onClicked", arguments: nil)
      result(nil)

    case "showContextMenu":
      showNativeContextMenu()
      result(nil)

    case "reportError":
      // Uncaught Dart error inside the render engine — relay it through the
      // existing diagnostic pipeline into the main engine's persistent
      // AppLogger, exactly like the boot-race timeout below. See
      // `shared_render_engine_helpers.dart`'s `RenderChannel.reportError`.
      if let args = call.arguments as? [String: Any], let message = args["message"] as? String {
        NSLog("[button] render engine reported an error: \(message)")
        channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": true])
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func showNativeContextMenu() {
    if contextMenuItems.isEmpty {
      // No items configured — mirror the old native behaviour: fall back to
      // the secondary-click event on the public channel.
      channel.invokeMethod("onSecondaryClicked", arguments: nil)
      return
    }
    let menu = NSMenu()
    for item in contextMenuItems {
      if item.label == "---" {
        menu.addItem(NSMenuItem.separator())
        continue
      }
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
    channel.invokeMethod("onContextMenu", arguments: ["id": id])
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
    latestState = nil
    channel.setMethodCallHandler(nil)
  }
}
