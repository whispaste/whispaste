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
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
