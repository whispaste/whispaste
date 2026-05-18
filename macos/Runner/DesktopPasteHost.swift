import Cocoa
import FlutterMacOS
import os.log

/// Native macOS host for desktop auto-paste via CGEvent.
///
/// Captures the frontmost application before recording starts, then
/// re-activates it and sends Cmd+V to paste the transcription result.
/// Requires the user to grant Accessibility permission.
class DesktopPasteHost {
  private static let logger = OSLog(subsystem: "com.whispaste.paste", category: "DesktopPasteHost")

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
        result(["status": "post_failed", "detail": "missing delayMs argument"])
        return
      }
      pasteClipboard(delayMs: delayMs, result: result)

    case "checkCapability":
      let prompt = (call.arguments as? [String: Any])?["prompt"] as? Bool ?? false
      result(checkCapability(prompt: prompt))

    case "repairTccEntries":
      result(repairTccEntries())

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
      os_log("captureTarget: no frontmost application — cleared target", log: Self.logger, type: .info)
      return false
    }
    if front.bundleIdentifier == Bundle.main.bundleIdentifier {
      targetApp = nil
      os_log("captureTarget: WhisPaste is frontmost — cleared target", log: Self.logger, type: .info)
      return false
    }
    targetApp = front
    os_log("captureTarget: captured %{public}@", log: Self.logger, type: .info, front.bundleIdentifier ?? "<unknown>")
    return true
  }

  /// Re-activates the captured target app and sends Cmd+V.
  ///
  /// Returns a structured `{status: String, detail: String?}` so Dart can
  /// distinguish silent failure modes (no target / post failed / blocked)
  /// and surface the right guidance to the user.
  ///
  /// **No `AXIsProcessTrusted()` pre-check.** That call returns `false` on
  /// ad-hoc-signed apps even when the user has toggled the Accessibility
  /// permission on, because TCC binds permissions to a code requirement
  /// (which includes the content hash) — every rebuild produces a new
  /// hash so the visible toggle no longer applies to the running binary.
  /// Both CGEvent and AppleScript channels are attempted unconditionally;
  /// if neither lands, the AX state is included in the detail for triage.
  private func pasteClipboard(delayMs: Int, result: @escaping FlutterResult) {
    guard let app = targetApp else {
      os_log("pasteClipboard: no target app — refusing", log: Self.logger, type: .error)
      result(["status": "no_target", "detail": "no target captured at paste time"])
      return
    }

    let trusted = AXIsProcessTrusted()
    os_log("pasteClipboard: AXIsProcessTrusted=%{public}@ (informational — not gating)",
           log: Self.logger, type: .info, String(trusted))

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
    let bundle = app.bundleIdentifier ?? "<unknown>"
    let deadline: DispatchTime = .now() + .milliseconds(clampedDelay)
    DispatchQueue.main.asyncAfter(deadline: deadline) {
      // Channel A: CGEvent — needs Accessibility permission. The post()
      // call is void and CG never reports delivery failure, so the only
      // signal we have for "the OS dropped it silently" is AX state.
      let cgOk = self.sendCmdV()

      // Channel B: AppleScript — uses the AppleEvents (Automation) TCC
      // service, an independent permission channel. On first call macOS
      // shows "<app> would like to control 'System Events'" and remembers
      // the user's choice; subsequent calls return -1743 if denied or
      // execute silently if allowed.
      let appleScriptResult = self.sendCmdVViaAppleScript()

      let detail = "ax=\(trusted) cg=\(cgOk) as=\(appleScriptResult) target=\(bundle)"
      os_log("pasteClipboard: %{public}@", log: Self.logger, type: .info, detail)

      // Honest success determination — CGEvent only counts when AX is
      // actually granted (otherwise the event was silently dropped).
      // AppleScript "ok" is trustworthy because System Events propagates
      // a clear error code when permission is missing.
      let cgLanded = cgOk && trusted
      let asLanded = appleScriptResult == "ok"

      if cgLanded || asLanded {
        result(["status": "success", "detail": detail])
        return
      }

      // Neither channel could land the keystroke. Map to the most
      // actionable failure code so the UI shows targeted guidance.
      if appleScriptResult == "permission_missing" && !trusted {
        // Both TCC services denied — classic ad-hoc-signature / stale
        // entry symptom on macOS Sequoia. The repair tool runs
        // `tccutil reset` for both services to force fresh prompts.
        result([
          "status": "no_accessibility",
          "detail": detail,
          "hint": "both_tcc_services_denied",
        ])
        return
      }
      result(["status": "post_failed", "detail": detail])
    }
  }

  /// Wipes stale TCC entries for both permission channels Auto-Paste uses.
  ///
  /// On macOS, TCC binds permissions to a code requirement that includes
  /// the binary's content hash. Ad-hoc-signed apps (no Team ID) get a new
  /// requirement on every rebuild, so the visible System Settings toggle
  /// may show as "ON" for an old entry that no longer applies to the
  /// running binary — `AXIsProcessTrusted()` returns false and CGEvent
  /// posts are silently dropped, even though the user "granted" it.
  ///
  /// `tccutil reset <service> <bundleId>` removes all entries for that
  /// service/app pair. The next attempt triggers a fresh prompt that
  /// binds to the current binary's hash.
  ///
  /// Returns `{ax: <int>, ae: <int>, error: <string?>}` with the count
  /// of removed entries per service (or -1 on failure).
  private func repairTccEntries() -> [String: Any] {
    let bundleId = Bundle.main.bundleIdentifier ?? "com.whispaste.whispaste"
    var result: [String: Any] = [:]
    result["ax"] = runTccReset(service: "Accessibility", bundleId: bundleId)
    result["ae"] = runTccReset(service: "AppleEvents", bundleId: bundleId)
    os_log("repairTccEntries: ax=%{public}@ ae=%{public}@",
           log: Self.logger, type: .info,
           String(describing: result["ax"]!),
           String(describing: result["ae"]!))
    return result
  }

  private func runTccReset(service: String, bundleId: String) -> Int {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
    task.arguments = ["reset", service, bundleId]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    do {
      try task.run()
      task.waitUntilExit()
    } catch {
      return -1
    }

    if task.terminationStatus != 0 {
      return -1
    }
    // tccutil prints one "Successfully reset" line per cleared entry.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""
    return output.components(separatedBy: "\n")
      .filter { $0.contains("Successfully reset") }
      .count
  }

  /// Attempts a Cmd+V paste via AppleScript's `System Events.keystroke`.
  ///
  /// This is a *second* permission channel (Automation, not Accessibility)
  /// that ad-hoc-signed apps sometimes have access to when CGEvent posting
  /// silently fails. The first call triggers macOS's "WhisPaste would like
  /// to control 'System Events'" prompt — granting it stores a permanent
  /// allow rule under TCC service `kTCCServiceAppleEvents`.
  ///
  /// Returns one of: `"ok"`, `"permission_missing"`, `"error:<details>"`.
  private func sendCmdVViaAppleScript() -> String {
    let source = """
      tell application "System Events" to keystroke "v" using {command down}
      """
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else {
      return "error:script_compile_failed"
    }
    script.executeAndReturnError(&error)
    if let err = error {
      let code = err["NSAppleScriptErrorNumber"] as? Int ?? 0
      // -1743 = not allowed to send Apple events; -600 = no app; -1719/-1728 = misc
      if code == -1743 {
        return "permission_missing"
      }
      return "error:\(code):\(err["NSAppleScriptErrorMessage"] ?? "?")"
    }
    return "ok"
  }

  /// Probes whether Auto-Paste would work right now — without pasting.
  ///
  /// When [prompt] is `true`, calls `AXIsProcessTrustedWithOptions` with
  /// the prompt flag set. macOS shows its own permission dialog once per
  /// process per session, opening System Settings → Privacy & Security →
  /// Accessibility for the user. Subsequent prompts within the same
  /// process are silently ignored by the OS — this is intentional.
  private func checkCapability(prompt: Bool) -> [String: Any] {
    let trusted: Bool
    if prompt {
      let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    } else {
      trusted = AXIsProcessTrusted()
    }
    os_log("checkCapability: trusted=%{public}@ prompt=%{public}@",
           log: Self.logger, type: .info,
           String(trusted), String(prompt))
    if trusted {
      return ["status": "ready", "canPrompt": false]
    }
    // canPrompt: macOS only shows the prompt once per process. We don't
    // know across calls whether the user already saw it, so we
    // optimistically report true — the worst case is the OS silently
    // ignoring a duplicate prompt request.
    return ["status": "permission_missing", "canPrompt": true,
            "detail": "AXIsProcessTrusted=false"]
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
