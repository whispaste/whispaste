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

    case "getTargetBundleId":
      result(targetApp?.bundleIdentifier)

    case "pasteClipboard":
      guard let args = call.arguments as? [String: Any],
            let delayMs = args["delayMs"] as? Int else {
        result(false)
        return
      }
      pasteClipboard(delayMs: delayMs, result: result)

    case "destroy":
      targetApp = nil
      channel.setMethodCallHandler(nil)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Captures the current frontmost application (excluding ourselves).
  ///
  /// Returns false and clears any prior target when WhisPaste itself is
  /// frontmost, so a subsequent paste can't fire into a stale target from
  /// an earlier session. Without this, FAB-started recordings would paste
  /// into whatever app happened to be frontmost on the previous hotkey
  /// press — usually nothing, or the wrong app.
  private func captureTarget() -> Bool {
    guard let front = NSWorkspace.shared.frontmostApplication else {
      targetApp = nil
      NSLog("[DesktopPasteHost] captureTarget: no frontmost application — cleared target")
      return false
    }
    if front.bundleIdentifier == Bundle.main.bundleIdentifier {
      targetApp = nil
      NSLog("[DesktopPasteHost] captureTarget: WhisPaste is frontmost — cleared target")
      return false
    }
    targetApp = front
    NSLog("[DesktopPasteHost] captureTarget: captured \(front.bundleIdentifier ?? "<unknown>")")
    return true
  }

  /// Re-activates the captured target app and sends Cmd+V.
  ///
  /// The Flutter result callback is fired only after `sendCmdV()` actually
  /// runs, so the Dart layer learns the real outcome instead of an
  /// optimistic `true` returned before any keystroke is posted.
  private func pasteClipboard(delayMs: Int, result: @escaping FlutterResult) {
    guard let app = targetApp else {
      NSLog("[DesktopPasteHost] pasteClipboard: no target app — refusing")
      result(false)
      return
    }

    // Accessibility is required for CGEventPost. Without it the events are
    // silently dropped by the OS and the user sees nothing happen, so make
    // it a hard stop instead of an optimistic warning.
    if !AXIsProcessTrusted() {
      NSLog("[DesktopPasteHost] pasteClipboard: Accessibility not granted — aborting")
      result(false)
      return
    }

    // Clamp delay to a reasonable range (0–5 seconds).
    let clampedDelay = max(0, min(delayMs, 5000))

    // Activate the target app. macOS 14 deprecated the no-arg form in
    // favour of the options-taking variant; on older systems both exist
    // and behave identically.
    if #available(macOS 14.0, *) {
      app.activate(options: [])
    } else {
      app.activate(options: [.activateIgnoringOtherApps])
    }

    // Brief delay to allow the target window to come to front before we
    // post the keystroke, then report the real outcome to Dart.
    let deadline: DispatchTime = .now() + .milliseconds(clampedDelay)
    DispatchQueue.main.asyncAfter(deadline: deadline) {
      let posted = self.sendCmdV()
      if !posted {
        NSLog("[DesktopPasteHost] pasteClipboard: sendCmdV failed to post events")
      }
      result(posted)
    }
  }

  /// Posts Cmd+V via CGEvent to the frontmost application. Returns true
  /// when both events were successfully created and posted.
  private func sendCmdV() -> Bool {
    let vKeyCode: CGKeyCode = 0x09 // 'v' key

    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: vKeyCode, keyDown: false) else {
      return false
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand

    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }
}
