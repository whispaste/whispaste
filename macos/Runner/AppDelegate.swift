import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

  private var desktopPasteHost: DesktopPasteHost?
  private var floatingButtonHost: FloatingButtonHost?
  private var floatingOverlayHost: FloatingOverlayHost?
  private var lifecycleChannel: FlutterMethodChannel?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Return false so close-to-tray keeps the app alive in background.
    return false
  }

  /// Re-show the main window when the user clicks the Dock icon while hidden.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      mainFlutterWindow?.makeKeyAndOrderFront(nil)
      NSApp.setActivationPolicy(.regular)
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    guard let window = mainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else {
      return
    }

    let messenger = controller.engine.binaryMessenger

    // Register native MethodChannel hosts.
    desktopPasteHost = DesktopPasteHost(messenger: messenger)
    floatingButtonHost = FloatingButtonHost(messenger: messenger)
    floatingOverlayHost = FloatingOverlayHost(messenger: messenger)

    // Lifecycle channel: activation policy toggle for close-to-tray.
    lifecycleChannel = FlutterMethodChannel(
      name: "com.whispaste.app_lifecycle",
      binaryMessenger: messenger
    )
    lifecycleChannel?.setMethodCallHandler { [weak self] call, result in
      self?.handleLifecycleCall(call, result: result)
    }
  }

  private func handleLifecycleCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "setActivationPolicy":
      guard let args = call.arguments as? [String: Any],
            let policy = args["policy"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'policy'", details: nil))
        return
      }
      switch policy {
      case "regular":
        NSApp.setActivationPolicy(.regular)
      case "accessory":
        NSApp.setActivationPolicy(.accessory)
      default:
        result(FlutterError(code: "UNKNOWN_POLICY", message: "Unknown policy: \(policy)", details: nil))
        return
      }
      result(nil)

    case "requestUserAttention":
      // Critical request → dock icon bounces until user activates the app.
      // Informational request → bounces once. We always use critical for
      // paste failures so the bounce keeps going until the user notices,
      // matching the persistent nature of the underlying issue (the user
      // has a TODO that won't go away on its own).
      let level = (call.arguments as? [String: Any])?["level"] as? String ?? "critical"
      let req: NSApplication.RequestUserAttentionType =
        level == "informational" ? .informationalRequest : .criticalRequest
      let token = NSApp.requestUserAttention(req)
      // Returning the token allows Dart to cancel the bounce later via
      // `cancelUserAttentionRequest:` once the issue is resolved.
      result(token)

    case "cancelUserAttentionRequest":
      if let token = (call.arguments as? [String: Any])?["token"] as? Int {
        NSApp.cancelUserAttentionRequest(token)
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
