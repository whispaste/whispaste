import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {

  private var desktopPasteHost: DesktopPasteHost?
  private var floatingButtonHost: FloatingButtonHost?
  private var floatingOverlayHost: FloatingOverlayHost?
  private var audioRoutingHost: AudioRoutingHost?
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
    audioRoutingHost = AudioRoutingHost(messenger: messenger)

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

    case "restart":
      // Programmatic relaunch — used by the Auto-Paste onboarding step when
      // the user hits the ad-hoc-signed TCC-cache mismatch on macOS. After
      // `tccutil reset` has wiped stale entries, macOS only re-evaluates the
      // app's trust state for a *fresh* process, so the only reliable way
      // to get the OS to recognise the granted permission is to relaunch
      // WhisPaste itself.
      result(nil)
      let bundlePath = Bundle.main.bundlePath
      // Spawn a detached helper that waits for us to exit, then re-opens
      // the .app bundle. Using `/usr/bin/open -n <bundlePath>` from a
      // detached subshell ensures the relaunched process is not parented
      // to this one and inherits no Accessibility trust from the original.
      let pid = ProcessInfo.processInfo.processIdentifier
      let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done
        /usr/bin/open -n "\(bundlePath)"
        """
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/bin/sh")
      task.arguments = ["-c", script]
      do {
        try task.run()
      } catch {
        // If we can't spawn the helper there's no clean fallback — bail
        // without terminating so the user can manually relaunch.
        return
      }
      // Give Dart a moment to flush its method-channel reply, then quit.
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) {
        NSApp.terminate(nil)
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
