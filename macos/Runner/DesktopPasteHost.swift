import Cocoa
import FlutterMacOS

/// Native macOS host for desktop auto-paste via CGEvent.
///
/// Captures the frontmost application before recording starts, then
/// re-activates it and sends Cmd+V to paste the transcription result.
/// Requires the user to grant Accessibility permission.
class DesktopPasteHost {
  private var channel: FlutterMethodChannel
  private var targetApp: NSRunningApplication?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.desktop_paste",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "captureTarget":
      let captured = captureTarget()
      result(captured)

    case "pasteClipboard":
      guard let args = call.arguments as? [String: Any],
            let delayMs = args["delayMs"] as? Int else {
        result(false)
        return
      }
      let success = pasteClipboard(delayMs: delayMs)
      result(success)

    case "destroy":
      targetApp = nil
      channel.setMethodCallHandler(nil)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Captures the current frontmost application (excluding ourselves).
  private func captureTarget() -> Bool {
    guard let front = NSWorkspace.shared.frontmostApplication,
          front.bundleIdentifier != Bundle.main.bundleIdentifier else {
      return false
    }
    targetApp = front
    return true
  }

  /// Re-activates the captured target app and sends Cmd+V.
  private func pasteClipboard(delayMs: Int) -> Bool {
    guard let app = targetApp else { return false }

    // Check Accessibility permission (required for CGEventPost).
    if !AXIsProcessTrusted() {
      NSLog("[DesktopPasteHost] Accessibility not granted — paste will fail")
    }

    // Clamp delay to a reasonable range (0–5 seconds).
    let clampedDelay = max(0, min(delayMs, 5000))

    // Activate the target app.
    app.activate()

    // Brief delay to allow the target window to come to front.
    // Dispatched asynchronously to avoid blocking the main thread.
    let deadline: DispatchTime = .now() + .milliseconds(clampedDelay)
    DispatchQueue.main.asyncAfter(deadline: deadline) {
      self.sendCmdV()
    }

    return true
  }

  /// Posts Cmd+V via CGEvent to the frontmost application.
  private func sendCmdV() {
    let vKeyCode: CGKeyCode = 0x09 // 'v' key

    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
      return
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
  }
}
