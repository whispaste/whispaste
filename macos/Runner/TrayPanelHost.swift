import Carbon.HIToolbox
import Cocoa
import FlutterMacOS
import os.log

/// MethodChannel host of the tray / menu bar panel on macOS (#920, slice 1).
///
/// Same shell as `SnippetPickerHost` (ADR 0002): the panel is a lifecycle-only
/// `NSPanel` hosting a second Flutter engine (`trayPanelMain`) that paints a
/// snapshot the main engine sends. Differences from the picker:
/// - The app is never activated. The panel is key without activation, so the
///   frontmost app and with it the paste target stay untouched; a dictation
///   started from the panel behaves exactly like one started by the hotkey.
/// - The engine boots lazily on the first click, not at launch (no startup
///   cost, Nordstern 6). If it is not ready within `bootBudget`, `toggle`
///   answers `ok: false` and the main engine falls back to the native menu;
///   the engine keeps booting, so the next click opens the panel.
/// - Anchored under the status item: horizontally centred on the pointer at
///   the click (the pointer is on the icon), top edge at the bottom of the
///   menu bar, clamped to the screen.
///
/// Channels: `com.whispaste.tray_panel` (main engine: `toggle`, `update`,
/// `hide`, `destroy`; events `onAction`, `onDismissed`,
/// `onRenderEngineDiagnostic`) and `com.whispaste.tray_panel_render` (panel
/// engine: `ready`, `action`, `cancel`, `reportError`; to it `setContent`,
/// `panelHidden`).
class TrayPanelHost: NSObject, NSWindowDelegate {
  private static let logger = OSLog(subsystem: "com.whispaste.tray_panel", category: "TrayPanelHost")

  /// Card 320 x ~190 plus 20 px shadow inset on every side.
  private static let contentSize = NSSize(width: 360, height: 232)
  private static let bootBudget: DispatchTimeInterval = .milliseconds(700)
  /// A click on the status item resigns key first, then arrives as a click;
  /// without this window the second click would close and re-open the panel.
  private static let reopenGuard: TimeInterval = 0.3

  private let channel: FlutterMethodChannel
  private var panel: TrayPanelPanel?
  private var renderEngine: FlutterEngine?
  private var renderViewController: FlutterViewController?
  private var renderChannel: FlutterMethodChannel?
  private var renderReady = false
  private var renderBootStartedAt: DispatchTime?

  private var pendingContent: [String: Any]?
  private var pendingPointer: NSPoint?
  private var pendingResult: FlutterResult?
  private var bootTimeout: DispatchWorkItem?

  private var isDismissing = false
  private var lastDismissAt: Date = .distantPast
  private var escapeMonitor: Any?
  private var globalClickMonitor: Any?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.whispaste.tray_panel", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler(handle)
    // Escape reaches the Flutter view too, but the picker needed this monitor
    // for the embedder's text-input proxy; keep the same guarantee.
    escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, self.isShown, event.keyCode == kVK_Escape else { return event }
      self.dismiss()
      return nil
    }
  }

  private var isShown: Bool {
    guard let p = panel else { return false }
    return p.isVisible && !isDismissing
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "toggle":
      guard let content = call.arguments as? [String: Any] else {
        result(["ok": false])
        return
      }
      toggle(content: content, result: result)
    case "update":
      if let content = call.arguments as? [String: Any], isShown {
        renderChannel?.invokeMethod("setContent", arguments: content)
      }
      result(nil)
    case "hide":
      dismiss()
      result(nil)
    case "destroy":
      teardown()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Toggle

  private func toggle(content: [String: Any], result: @escaping FlutterResult) {
    if isShown {
      dismiss()
      result(["ok": true])
      return
    }
    // The click that just closed the panel by resigning key: stay closed.
    if Date().timeIntervalSince(lastDismissAt) < Self.reopenGuard {
      result(["ok": true])
      return
    }
    // Read the pointer now: the anchor is where the user clicked the icon.
    let pointer = NSEvent.mouseLocation
    ensurePanel()
    if renderReady {
      present(content: content, pointer: pointer)
      result(["ok": true])
      return
    }
    // Engine still booting: wait up to the budget, then let the menu take over.
    pendingResult?(["ok": false])
    bootTimeout?.cancel()
    pendingContent = content
    pendingPointer = pointer
    pendingResult = result
    let work = DispatchWorkItem { [weak self] in
      guard let self, let pending = self.pendingResult else { return }
      self.pendingResult = nil
      self.pendingContent = nil
      os_log("render engine not ready within budget, falling back to the menu", log: Self.logger, type: .info)
      pending(["ok": false])
    }
    bootTimeout = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.bootBudget, execute: work)
  }

  private func present(content: [String: Any], pointer: NSPoint) {
    guard let p = panel else { return }
    // The last measured height is kept; a later `resize` corrects it in place.
    p.setFrameOrigin(anchoredOrigin(pointer: pointer, size: p.frame.size))

    var payload = content
    payload["shown"] = true
    renderChannel?.invokeMethod("setContent", arguments: payload)

    isDismissing = false
    p.orderFrontRegardless()
    // See SnippetPickerHost.show: re-attach so AppKit redoes the appearance
    // cycle and the reused Flutter view repaints.
    if let vc = renderViewController {
      p.contentViewController = nil
      p.contentViewController = vc
    }
    // Key without activating the app: the paste target stays the frontmost app.
    p.makeKey()
    p.makeFirstResponder(renderViewController?.view)
    installGlobalClickMonitor()
  }

  // MARK: - Dismiss

  private func dismiss() {
    guard !isDismissing, let p = panel, p.isVisible else { return }
    isDismissing = true
    defer { isDismissing = false }
    lastDismissAt = Date()
    removeGlobalClickMonitor()
    p.orderOut(nil)
    renderChannel?.invokeMethod("panelHidden", arguments: nil)
    channel.invokeMethod("onDismissed", arguments: nil)
  }

  /// Clicks in other apps do not resign the key status of a non-activating
  /// panel reliably, so they are watched globally while the panel is open.
  private func installGlobalClickMonitor() {
    removeGlobalClickMonitor()
    globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    ) { [weak self] _ in
      DispatchQueue.main.async { self?.dismiss() }
    }
  }

  private func removeGlobalClickMonitor() {
    if let m = globalClickMonitor {
      NSEvent.removeMonitor(m)
      globalClickMonitor = nil
    }
  }

  // MARK: - Positioning

  private func anchoredOrigin(pointer: NSPoint, size: NSSize) -> NSPoint {
    let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { return pointer }
    // The 20 px shadow inset sits inside the window, so the visible card
    // starts a little below the menu bar edge.
    let x = min(max(pointer.x - size.width / 2, visible.minX), visible.maxX - size.width)
    let y = max(visible.maxY - size.height + 12, visible.minY)
    return NSPoint(x: x, y: y)
  }

  // MARK: - Engine

  private func ensurePanel() {
    if panel == nil {
      let p = TrayPanelPanel(contentSize: Self.contentSize)
      p.delegate = self
      panel = p
    }
    if renderViewController == nil { bootRenderEngine() }
  }

  private func bootRenderEngine() {
    guard let p = panel else { return }
    renderReady = false
    if renderEngine != nil, renderViewController == nil {
      renderEngine?.shutDownEngine()
      renderEngine = nil
    }
    renderBootStartedAt = DispatchTime.now()
    let engine = FlutterEngine(name: "tray_panel", project: nil)
    let didRun = engine.run(withEntrypoint: "trayPanelMain")
    guard didRun else {
      renderEngine = engine
      return
    }
    let vc = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    vc.backgroundColor = .clear
    let renderCh = FlutterMethodChannel(
      name: "com.whispaste.tray_panel_render",
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

  private func handleRenderCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      renderReady = true
      if let start = renderBootStartedAt {
        let ms = Double(DispatchTime.now().uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000
        // Measurement input for ADR 0038: engine boot time and resident memory.
        os_log(
          "render engine ready after %{public}.0f ms, resident %{public}.1f MB",
          log: Self.logger, type: .info, ms, Self.residentMegabytes()
        )
      }
      renderBootStartedAt = nil
      if let pending = pendingResult, let content = pendingContent {
        bootTimeout?.cancel()
        pendingResult = nil
        pendingContent = nil
        present(content: content, pointer: pendingPointer ?? NSEvent.mouseLocation)
        pending(["ok": true])
      }
      result(nil)
    case "action":
      guard let args = call.arguments as? [String: Any], let action = args["action"] as? String else {
        result(nil)
        return
      }
      // Close first: the panel never holds focus while the action runs.
      dismiss()
      channel.invokeMethod("onAction", arguments: ["action": action])
      result(nil)
    case "cancel":
      dismiss()
      result(nil)
    case "resize":
      // The engine reports its painted height (content, picker page); the top
      // edge stays under the menu bar, the window grows downwards.
      if let p = panel, let args = call.arguments as? [String: Any],
         let height = (args["height"] as? NSNumber)?.doubleValue, height > 0 {
        let frame = p.frame
        let size = NSSize(width: Self.contentSize.width, height: CGFloat(height).rounded(.up))
        if abs(frame.height - size.height) >= 1 {
          p.setFrame(
            NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height),
            display: true
          )
        }
      }
      result(nil)
    case "reportError":
      if let args = call.arguments as? [String: Any], let message = args["message"] as? String {
        os_log("render engine error: %{public}@", log: Self.logger, type: .error, message)
        channel.invokeMethod("onRenderEngineDiagnostic", arguments: ["message": message, "isError": true])
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func residentMegabytes() -> Double {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
      }
    }
    return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
  }

  // MARK: - NSWindowDelegate

  func windowDidResignKey(_ notification: Notification) {
    dismiss()
  }

  // MARK: - Teardown

  private func teardown() {
    if let m = escapeMonitor { NSEvent.removeMonitor(m); escapeMonitor = nil }
    removeGlobalClickMonitor()
    bootTimeout?.cancel()
    pendingResult?(["ok": false])
    pendingResult = nil
    renderChannel?.setMethodCallHandler(nil)
    panel?.delegate = nil
    panel?.close()
    panel = nil
    renderViewController = nil
    renderChannel = nil
    renderEngine?.shutDownEngine()
    renderEngine = nil
    renderReady = false
    channel.setMethodCallHandler(nil)
  }
}
