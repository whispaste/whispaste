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

    case "typeText":
      guard let args = call.arguments as? [String: Any],
            let text = args["text"] as? String,
            let delayMs = args["delayMs"] as? Int else {
        result(["status": "post_failed", "detail": "missing text/delayMs argument"])
        return
      }
      typeText(text: text, delayMs: delayMs, result: result)

    case "checkCapability":
      let prompt = (call.arguments as? [String: Any])?["prompt"] as? Bool ?? false
      result(checkCapability(prompt: prompt))

#if MAS_BUILD
    // Mac App Store build: the TCC self-heal handler is excluded entirely —
    // its only implementation, runTccReset(), shells out to /usr/bin/tccutil
    // via Process(), which is not permitted in the sandbox and would leave a
    // Process/tccutil symbol in the binary for Apple's static scan
    // (Guideline 2.5.2). Unlike auto-paste/type itself, kAutoPasteSupported
    // being true does NOT bring this handler back — the Dart-side caller
    // (MacOSDesktopPasteController.repairTccEntries()) IS reachable in MAS
    // builds now, but an unrecognised "repairTccEntries" call here falls
    // through to `default` below, which Flutter surfaces to Dart as a
    // MissingPluginException; the Dart side already catches that and
    // returns TccRepairResult.unsupported() (see channel_desktop_paste_
    // controller.dart). No repair tool exists for MAS because the ad-hoc-
    // signature TCC-hash-instability problem it fixes doesn't apply to a
    // properly Apple-signed App Store binary.
#else
    case "repairTccEntries":
      result(repairTccEntries())
#endif

    case "diagnosticPaste":
      let demoText = (call.arguments as? [String: Any])?["demoText"] as? String ?? ""
      diagnosticPaste(demoText: demoText, result: result)

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

  /// Whether this build's synthetic-keystroke channel is currently
  /// permitted by the OS.
  ///
  /// Developer-ID builds keep the existing, proven Accessibility-gated
  /// channel (see the `#else` branch's doc below). Mac App Store builds use
  /// a *different* TCC service — `PostEvent` — because the sandbox blocks
  /// the Accessibility API outright but allows `CGEvent.post` under this
  /// separate, narrower grant (confirmed by Apple DTS and empirically
  /// verified for WhisPaste; see the Phase 0 proof in the direct-typing
  /// plan). `AXIsProcessTrusted()` would always read `false` in a sandboxed
  /// process regardless of the PostEvent grant, so it is the wrong check
  /// here — using it was the "App Sandbox blocks this" misconception this
  /// build variant used to encode.
  private func canPostSyntheticEvents() -> Bool {
#if MAS_BUILD
    return CGPreflightPostEventAccess()
#else
    return AXIsProcessTrusted()
#endif
  }

  /// Re-activates the captured target app and sends Cmd+V.
  ///
  /// Returns a structured `{status: String, detail: String?}` so Dart can
  /// distinguish silent failure modes (no target / post failed / blocked)
  /// and surface the right guidance to the user.
  ///
  /// **No pre-check gating the attempt itself.** On the Developer-ID build,
  /// `AXIsProcessTrusted()` returns `false` on ad-hoc-signed apps even when
  /// the user has toggled the Accessibility permission on, because TCC
  /// binds permissions to a code requirement (which includes the content
  /// hash) — every rebuild produces a new hash so the visible toggle no
  /// longer applies to the running binary. Both CGEvent and AppleScript
  /// channels are attempted unconditionally there; if neither lands, the AX
  /// state is included in the detail for triage. The Mac App Store build
  /// has only the CGEvent/PostEvent channel — no AppleScript fallback (the
  /// AppleEvents/Automation TCC service isn't usable from the sandbox).
  private func pasteClipboard(delayMs: Int, result: @escaping FlutterResult) {
    guard let app = targetApp else {
      os_log("pasteClipboard: no target app — refusing", log: Self.logger, type: .error)
      result(["status": "no_target", "detail": "no target captured at paste time"])
      return
    }

    let trusted = canPostSyntheticEvents()
    os_log("pasteClipboard: canPostSyntheticEvents=%{public}@ (informational — not gating)",
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
      // Channel A: CGEvent — needs the permission canPostSyntheticEvents()
      // checks. The post() call is void and CG never reports delivery
      // failure, so the only signal we have for "the OS dropped it
      // silently" is that permission state.
      let cgOk = self.sendCmdV()
      // CGEvent only actually lands when the permission is granted
      // (otherwise the event is silently dropped). This is also the gate
      // for the fallback below.
      let cgLanded = cgOk && trusted

#if MAS_BUILD
      // No AppleEvents/Automation channel in the sandbox — PostEvent/CGEvent
      // is the only channel available, matching the Phase 0 proof.
      let appleScriptResult = "unsupported"
#else
      // Channel B: AppleScript fallback — uses the AppleEvents (Automation) TCC
      // service, an independent permission channel. Run it ONLY when CGEvent
      // could not have landed; running both when both permissions are granted
      // pastes the clipboard twice (double-paste bug).
      let appleScriptResult = cgLanded ? "skipped" : self.sendCmdVViaAppleScript()
#endif

      let detail = "trusted=\(trusted) cg=\(cgOk) as=\(appleScriptResult) target=\(bundle)"
      os_log("pasteClipboard: %{public}@", log: Self.logger, type: .info, detail)

      // AppleScript "ok" is trustworthy because System Events propagates a
      // clear error code when permission is missing.
      let asLanded = appleScriptResult == "ok"

      if cgLanded || asLanded {
        result(["status": "success", "detail": detail])
        return
      }

#if MAS_BUILD
      if !trusted {
        result([
          "status": "no_accessibility",
          "detail": detail,
          "hint": "postevent_denied",
        ])
        return
      }
#else
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
#endif
      result(["status": "post_failed", "detail": detail])
    }
  }

  /// Re-activates the captured target app and types [text] via synthetic
  /// Unicode keyboard events — no clipboard involved at all.
  ///
  /// Mirrors [pasteClipboard]'s target-capture/activate/delay structure and
  /// `{status, detail}` result shape, posting the transcript directly
  /// instead of a paste shortcut. Available on the Mac App Store build too
  /// — see [canPostSyntheticEvents].
  private func typeText(text: String, delayMs: Int, result: @escaping FlutterResult) {
    guard let app = targetApp else {
      os_log("typeText: no target app — refusing", log: Self.logger, type: .error)
      result(["status": "no_target", "detail": "no target captured at type time"])
      return
    }

    let trusted = canPostSyntheticEvents()
    os_log("typeText: canPostSyntheticEvents=%{public}@",
           log: Self.logger, type: .info, String(trusted))

    let clampedDelay = max(0, min(delayMs, 5000))

    if #available(macOS 14.0, *) {
      app.activate(options: [])
    } else {
      app.activate(options: [.activateIgnoringOtherApps])
    }

    let bundle = app.bundleIdentifier ?? "<unknown>"
    let deadline: DispatchTime = .now() + .milliseconds(clampedDelay)
    DispatchQueue.main.asyncAfter(deadline: deadline) {
      guard trusted else {
        let detail = "trusted=false target=\(bundle)"
        os_log("typeText: %{public}@", log: Self.logger, type: .info, detail)
        result(["status": "no_accessibility", "detail": detail])
        return
      }
      let posted = self.postUnicodeString(text)
      let detail = "trusted=true posted=\(posted) target=\(bundle) chars=\(text.count)"
      os_log("typeText: %{public}@", log: Self.logger, type: .info, detail)
      result(["status": posted ? "success" : "post_failed", "detail": detail])
    }
  }

#if MAS_BUILD
  // Mac App Store build: repairTccEntries()/runTccReset() are compiled out
  // entirely so the shipped binary contains no Process/tccutil symbols,
  // which Apple statically scans for (Guideline 2.5.2). The dispatch case
  // above is excluded to match — see the `handle` switch.
#else
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
    let bundleId = Bundle.main.bundleIdentifier ?? "de.whispaste.app"
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
#endif

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
#if MAS_BUILD
    // Mac App Store build: AppleEvents/Automation keystroke injection is not
    // permitted; compiled out so the shipped binary contains no NSAppleScript
    // "keystroke" payload. Never reached in practice — pasteClipboard()
    // doesn't call this under MAS_BUILD at all (see its own #if branch);
    // kept only as defense-in-depth against a careless future call site.
    return "unsupported"
#else
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
#endif
  }

  /// Probes whether Auto-Paste/Auto-Type would work right now — without
  /// actually posting anything.
  ///
  /// When [prompt] is `true` on the Developer-ID build, calls
  /// `AXIsProcessTrustedWithOptions` with the prompt flag set. macOS shows
  /// its own permission dialog once per process per session, opening
  /// System Settings → Privacy & Security → Accessibility for the user.
  /// Subsequent prompts within the same process are silently ignored by
  /// the OS — this is intentional. On the Mac App Store build, [prompt]
  /// instead calls `CGRequestPostEventAccess()` — the sandbox-compatible
  /// permission channel [canPostSyntheticEvents] checks.
  private func checkCapability(prompt: Bool) -> [String: Any] {
    let trusted: Bool
#if MAS_BUILD
    if prompt {
      trusted = CGRequestPostEventAccess()
    } else {
      trusted = CGPreflightPostEventAccess()
    }
#else
    if prompt {
      let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
      trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    } else {
      trusted = AXIsProcessTrusted()
    }
#endif
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
            "detail": "canPostSyntheticEvents=false"]
  }

  /// Onboarding "prove Auto-Paste works" probe.
  ///
  /// Backs up the current clipboard, writes `demoText`, synthesises Cmd+V
  /// into the frontmost window, briefly waits for the paste to land, and
  /// then restores the previous clipboard contents — even on the failure
  /// path. Returns one of:
  ///
  ///   - `{status: "success"}` — [canPostSyntheticEvents] is true and there
  ///     is a non-WhisPaste frontmost application that received the event.
  ///   - `{status: "no_frontmost"}` — no reachable frontmost window.
  ///   - `{status: "failure", detail: "not_trusted"}` — the permission
  ///     [canPostSyntheticEvents] checks is missing; the keystroke was
  ///     silently dropped.
  ///   - `{status: "failure", detail: "<reason>"}` — any other failure.
  ///
  /// All exits go through the same `restoreClipboard` defer so the user's
  /// pasteboard is never left in a half-modified state.
  private func diagnosticPaste(demoText: String, result: @escaping FlutterResult) {
    let pasteboard = NSPasteboard.general
    // Snapshot the pasteboard contents before mutating it so we can put
    // them back regardless of which exit path we take.
    let backup = self.backupPasteboard(pasteboard)
    var restored = false
    let restore: () -> Void = {
      if restored { return }
      restored = true
      self.restorePasteboard(pasteboard, backup: backup)
    }

    // The diagnostic paste is allowed to land *into* WhisPaste itself —
    // the onboarding sub-step puts a demo TextField on screen specifically
    // so the user can verify the keystroke synthesis works end-to-end
    // without having to alt-tab to another app first. (The regular
    // `pasteClipboard` flow keeps its self-target guard because there a
    // self-paste would mean the captured target was lost.) Only bail if
    // there is no frontmost app at all (e.g. login screen, screen locked).
    guard NSWorkspace.shared.frontmostApplication != nil else {
      os_log("diagnosticPaste: no frontmost application available",
             log: Self.logger, type: .info)
      result(["status": "no_frontmost"])
      return
    }

    // Write the demo text into the clipboard.
    pasteboard.clearContents()
    pasteboard.setString(demoText, forType: .string)

    let trusted = canPostSyntheticEvents()
    if !trusted {
      os_log("diagnosticPaste: canPostSyntheticEvents=false — keystroke would be silently dropped",
             log: Self.logger, type: .info)
      restore()
      result(["status": "failure", "detail": "not_trusted"])
      return
    }

    // Fire Cmd+V. We don't gate on `sendCmdV` return value alone — CG
    // never reports delivery failure — but combining it with the AX check
    // above gives us an honest "the OS would let this through" signal.
    let cgOk = self.sendCmdV()
    if !cgOk {
      os_log("diagnosticPaste: failed to create/post Cmd+V CGEvent",
             log: Self.logger, type: .error)
      restore()
      result(["status": "failure", "detail": "post_failed"])
      return
    }

    // Give the OS time to deliver the keystroke into the frontmost app and
    // for the focused TextField to read the pasteboard. 80 ms was too tight
    // on macOS 26 when WhisPaste pastes into its own demo field — Flutter's
    // text-field paste handler runs on the platform-message queue and was
    // sometimes still resolving when the restore wiped the clipboard.
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) {
      restore()
      result(["status": "success"])
    }
  }

  /// Captures the current pasteboard items so [restorePasteboard] can put
  /// the user's clipboard back after a diagnostic paste.
  private func backupPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
    guard let items = pasteboard.pasteboardItems else { return [] }
    return items.map { source in
      let copy = NSPasteboardItem()
      for type in source.types {
        if let data = source.data(forType: type) {
          copy.setData(data, forType: type)
        }
      }
      return copy
    }
  }

  /// Restores a previously captured pasteboard snapshot. Idempotent in
  /// practice — repeated invocations re-clear and re-write the same items.
  private func restorePasteboard(_ pasteboard: NSPasteboard,
                                 backup: [NSPasteboardItem]) {
    pasteboard.clearContents()
    if !backup.isEmpty {
      pasteboard.writeObjects(backup)
    }
  }

  /// Posts Cmd+V via CGEvent to the frontmost application. Returns true
  /// when both events were successfully created and posted.
  ///
  /// Available on the Mac App Store build too: CGEvent posting is gated by
  /// the sandbox-compatible PostEvent TCC service, not by the Accessibility
  /// API the sandbox actually blocks — see [canPostSyntheticEvents] and
  /// `build_config.dart`'s `kAutoPasteSupported` doc for the full reasoning
  /// (and the Phase 0 proof this reasoning is based on).
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

  /// Posts [text] as synthetic Unicode keydown/keyup event pairs via
  /// `CGEventKeyboardSetUnicodeString` — layout-independent, so umlauts,
  /// emoji, and other non-ASCII characters survive intact regardless of
  /// the active keyboard layout. Returns `true` when every chunk's events
  /// were successfully created and posted.
  ///
  /// Chunked into fixed-size UTF-16 windows: `CGEventKeyboardSetUnicodeString`
  /// has an undocumented, small per-event capacity for its Unicode payload —
  /// a long string posted in a single call is silently truncated by the OS.
  /// 20 UTF-16 units is the limit independently reported across CGEvent-based
  /// typing implementations (Qt, isamert.net) for this exact API; chunking to
  /// it avoids truncation. The `virtualKey` value is a placeholder —
  /// receiving apps read the attached Unicode payload, not the physical key
  /// code.
  ///
  /// Chunk boundaries never split a UTF-16 surrogate pair (e.g. most emoji
  /// are two UTF-16 units): if the unit right before a boundary is a high
  /// surrogate, the boundary shifts one unit later so the low surrogate
  /// stays in the same chunk — otherwise the emoji would be torn across two
  /// separate CGEvents and likely render as a replacement character.
  ///
  /// Pacing: `CGEventPost` only *queues* an event into the HID event system —
  /// it does not wait for the receiving app to actually consume it. Posting
  /// keyDown/keyUp pairs back-to-back with zero gap, and returning
  /// immediately after the final one, is a well-documented way to lose
  /// events (confirmed against real dictations: the trailing character was
  /// dropped noticeably often, matching the same class of bug reported for
  /// Hammerspoon's `hs.eventtap.keyStrokes` and other CGEvent-based typers —
  /// see Apple Developer Forums thread 13459). Two mitigations: a small gap
  /// between every keyDown/keyUp pair and between chunks, and a longer
  /// flush delay after the *last* chunk specifically, so the final event is
  /// actually drained by the target app's input pipeline before this
  /// function returns and the Flutter-side completion handler (which may
  /// trigger clipboard restore / UI updates that compete for the run loop)
  /// runs. `usleep` is safe here — this always runs on a background-queue
  /// dispatch (see `typeText`'s `asyncAfter` caller), never the visible UI
  /// thread's animation loop.
  private func postUnicodeString(_ text: String) -> Bool {
    let utf16 = Array(text.utf16)
    guard !utf16.isEmpty else { return true }

    let interEventDelayUs: useconds_t = 1_000 // 1ms
    let finalFlushDelayUs: useconds_t = 20_000 // 20ms

    let chunkSize = 20
    var index = 0
    while index < utf16.count {
      var end = min(index + chunkSize, utf16.count)
      if end < utf16.count, (0xD800...0xDBFF).contains(utf16[end - 1]) {
        end += 1
      }
      let chunk = Array(utf16[index..<end])
      let isLastChunk = end >= utf16.count

      guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
        return false
      }
      chunk.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        keyDown.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
        keyUp.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
      }
      keyDown.post(tap: .cghidEventTap)
      usleep(interEventDelayUs)
      keyUp.post(tap: .cghidEventTap)
      usleep(isLastChunk ? finalFlushDelayUs : interEventDelayUs)

      index = end
    }
    return true
  }
}
