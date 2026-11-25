import Cocoa
import Carbon.HIToolbox
import FlutterMacOS
import IOKit.hidsystem
import os.log

/// Virtual keycode that types [character] on the active keyboard layout.
///
/// Keycode 0x09 is the physical "V" position on ANSI keyboards only. On
/// Dvorak and similar layouts it types another letter, so a fixed Cmd+0x09
/// would paste or copy the wrong thing. [layoutCharacter] reports what each
/// keycode types with Command held; [fallback] applies when no keycode types
/// the character (or the layout cannot be read).
func keyCode(forCharacter character: String,
             layoutCharacter: (CGKeyCode) -> String?,
             fallback: CGKeyCode) -> CGKeyCode {
  for code in 0..<128 {
    let candidate = CGKeyCode(code)
    if layoutCharacter(candidate) == character {
      return candidate
    }
  }
  return fallback
}

/// The character the active keyboard layout types for [keyCode] while the
/// Command key is held, or `nil` when the layout data cannot be read.
///
/// Shortcuts follow the Command-state mapping, not the plain one: on
/// "Dvorak - QWERTY ⌘" the physical V key types "k" but Command+V is still on
/// it, and non-Latin layouts (Russian, Hebrew) map Command+key to the Latin
/// letter. Reading the plain mapping would send Command+K there.
func activeLayoutCharacter(for keyCode: CGKeyCode) -> String? {
  guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
    return nil
  }
  return commandCharacter(for: keyCode, in: source)
}

/// [commandCharacter] for one input source; split out so tests can read
/// installed layouts without switching the user's active one.
func commandCharacter(for keyCode: CGKeyCode, in source: TISInputSource) -> String? {
  guard let rawLayout = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
    return nil
  }
  let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue() as Data
  return layoutData.withUnsafeBytes { raw -> String? in
    guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
      return nil
    }
    var deadKeyState: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    // UCKeyTranslate takes the Carbon modifier bits shifted down by 8.
    let commandState = (UInt32(cmdKey) >> 8) & 0xFF
    let status = UCKeyTranslate(layout,
                                UInt16(keyCode),
                                UInt16(kUCKeyActionDown),
                                commandState,
                                UInt32(LMGetKbdType()),
                                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                &deadKeyState,
                                chars.count,
                                &length,
                                &chars)
    guard status == noErr, length > 0 else { return nil }
    return String(utf16CodeUnits: chars, count: length)
  }
}

/// Whether the keystroke undo (Cmd+Z) may go to the app with this bundle id
/// (#428, #581): only apps known to be plain text targets. Everything else,
/// terminals, editors with an embedded terminal and unknown apps included,
/// takes the clipboard path, the same fail-closed rule as the Linux and
/// Windows hosts. Extend the list with real bundle ids, never with guesses.
func isUndoSafeBundle(_ bundleId: String) -> Bool {
  let safe: Set<String> = [
    // Browsers.
    "com.google.chrome", "com.apple.safari", "org.mozilla.firefox",
    "com.microsoft.edgemac", "com.brave.browser", "com.vivaldi.vivaldi",
    "com.operasoftware.opera", "company.thebrowser.browser",
    // Plain editors and office.
    "com.apple.textedit", "com.apple.notes", "com.microsoft.word",
    "com.microsoft.excel", "com.microsoft.powerpoint",
    "com.microsoft.onenote.mac", "com.apple.iwork.pages",
    "com.apple.iwork.numbers", "com.apple.iwork.keynote", "md.obsidian",
    "abnerworks.typora", "notion.id",
    // Mail and chat.
    "com.apple.mail", "com.microsoft.outlook", "org.mozilla.thunderbird",
    "com.tinyspeck.slackmacgap", "com.hnc.discord", "ru.keepcoder.telegram",
    "org.whispersystems.signal-desktop", "com.microsoft.teams2",
    "com.apple.mobilesms", "im.riot.app",
  ]
  return safe.contains(bundleId.lowercased())
}

/// Why the keystroke undo is not sent, or `send`. The last check right before
/// Cmd+Z, the same questions Dart asked a moment earlier (#581).
enum UndoSendCheck: String {
  case send
  case noTarget = "no_target"
  case watcherInactive = "watcher_inactive"
  case foregroundChanged = "foreground_changed"
  case unsafeTarget = "unsafe_target"
  case userInput = "user_input"
}

/// Dart's tolerance for a hardware key-down reported right after our own
/// synthetic one (`syntheticKeyTolerance` in input_idle.dart).
let undoSyntheticKeyTolerance = 0.05

func decideUndoSend(
  targetBundle: String?,
  frontIsTarget: Bool,
  covers: Bool,
  sinceInsert: Double,
  keyIdle: Double,
  syntheticIdle: Double,
  mouseIdleOutsideApp: Double
) -> UndoSendCheck {
  guard let target = targetBundle, !target.isEmpty else { return .noTarget }
  if !covers { return .watcherInactive }
  if !frontIsTarget { return .foregroundChanged }
  if !isUndoSafeBundle(target) { return .unsafeTarget }
  let typed = keyIdle < sinceInsert &&
    keyIdle < syntheticIdle - undoSyntheticKeyTolerance
  if typed || mouseIdleOutsideApp < sinceInsert { return .userInput }
  return .send
}

/// Proof that no mouse click outside WhisPaste happened since the insert
/// (#581). A global monitor sees only events delivered to other apps, so the
/// click on the undo action in our own window is told apart from a foreign
/// one. It records the time of a click, nothing else (no position, no target).
/// Keys come from the system's own idle counter, which needs no monitor.
///
/// It comes up right before the paste keys go out (same moment as the hooks
/// on Windows and the watcher on Linux) and stops [span] after the last
/// insert. The undo contract is only answered while it runs and an insert
/// is on record, otherwise Dart copies the original text (fail-closed).
final class UndoWatch {
  static let span: TimeInterval = 300

  private let clock: () -> Double
  private let install: (@escaping () -> Void) -> Any?
  private let remove: (Any) -> Void
  private var monitor: Any?
  private var stopWork: DispatchWorkItem?
  private var startedAt: Double = 0
  private var lastOutsideDown: Double = 0
  private var insertAt: Double = 0

  /// [install] puts the mouse monitor in place and returns its token, or nil
  /// when the system refuses; [remove] takes it out again. Tests pass stubs.
  init(
    clock: @escaping () -> Double,
    install: @escaping (@escaping () -> Void) -> Any? = { onDown in
      NSEvent.addGlobalMonitorForEvents(
        matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
      ) { _ in onDown() }
    },
    remove: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
  ) {
    self.clock = clock
    self.install = install
    self.remove = remove
  }

  deinit { stop() }

  /// Called right before the paste keys go out: brings the monitor up when
  /// it is not running, records the insert and pushes the end back by [span].
  func markInsert() {
    if monitor == nil {
      monitor = install { [weak self] in
        guard let self else { return }
        self.lastOutsideDown = self.clock()
      }
      startedAt = monitor == nil ? 0 : clock()
      lastOutsideDown = 0
    }
    guard monitor != nil else {
      insertAt = 0
      return
    }
    insertAt = clock()
    scheduleStop()
  }

  /// A new target, a typed insert or a sent undo ends the proof of the
  /// earlier insert; the monitor itself keeps running until its end.
  func clearInsert() { insertAt = 0 }

  private func scheduleStop() {
    stopWork?.cancel()
    let work = DispatchWorkItem { [weak self] in self?.stop() }
    stopWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.span, execute: work)
  }

  func stop() {
    stopWork?.cancel()
    stopWork = nil
    if let monitor { remove(monitor) }
    monitor = nil
    startedAt = 0
    insertAt = 0
    lastOutsideDown = 0
  }

  /// The monitor runs and an insert is on record; it was installed right
  /// before that insert's keys, so every click since is seen.
  var covers: Bool { monitor != nil && insertAt > 0 }

  var sinceInsert: Double { insertAt > 0 ? clock() - insertAt : 0 }

  /// Seconds since the last click outside WhisPaste; without one, the time
  /// the monitor has been watching.
  var mouseIdleOutsideApp: Double {
    startedAt > 0 ? clock() - max(lastOutsideDown, startedAt) : 0
  }
}

/// Whether a key press is the plain undo shortcut: Cmd+Z with no other
/// modifier (Cmd+Shift+Z is redo). [characters] is the key's letter without
/// modifiers, so the shortcut follows the keyboard layout (AZERTY included).
func isUndoShortcut(flags: NSEvent.ModifierFlags, characters: String?) -> Bool {
  let mods = flags.intersection([.command, .shift, .option, .control])
  return mods == .command && characters?.lowercased() == "z"
}

/// The user's own Cmd+Z in another app right after an auto-paste, for the
/// model telemetry (#2078). A global key monitor runs only for the asked
/// span and only with the Accessibility permission WhisPaste already has
/// for pasting (no new prompt; in the sandboxed store build, which pastes
/// through PostEvent, it is usually missing and the watch reports unknown).
/// A global monitor only sees events delivered
/// to other apps, so a Cmd+Z in WhisPaste never counts; our own synthetic
/// keys are skipped by their source process. Only whether the shortcut came
/// is kept, never a key or character.
final class UndoShortcutWatch {
  private let trusted: () -> Bool
  private let install: (@escaping (NSEvent) -> Void) -> Any?
  private let remove: (Any) -> Void
  private var monitor: Any?
  private var stopWork: DispatchWorkItem?
  private(set) var seen = false

  init(
    trusted: @escaping () -> Bool = { AXIsProcessTrusted() },
    install: @escaping (@escaping (NSEvent) -> Void) -> Any? = { onKey in
      NSEvent.addGlobalMonitorForEvents(matching: [.keyDown], handler: onKey)
    },
    remove: @escaping (Any) -> Void = { NSEvent.removeMonitor($0) }
  ) {
    self.trusted = trusted
    self.install = install
    self.remove = remove
  }

  deinit { end() }

  /// Starts a watch of [seconds]; answers whether it runs and whether the
  /// previous watch saw the shortcut (that answer is then forgotten).
  func watch(seconds: Int) -> (watching: Bool, seen: Bool) {
    let previous = seen
    end()
    guard seconds > 0, trusted() else { return (false, previous) }
    monitor = install { [weak self] event in self?.handle(event) }
    guard monitor != nil else { return (false, previous) }
    let work = DispatchWorkItem { [weak self] in self?.stopMonitor() }
    stopWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
    return (true, previous)
  }

  /// Whether the shortcut came since [watch]; ends the watch.
  func take() -> Bool {
    let result = seen
    end()
    return result
  }

  private func handle(_ event: NSEvent) {
    let source = event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID)
    note(flags: event.modifierFlags, characters: event.charactersIgnoringModifiers,
         isRepeat: event.isARepeat, fromSelf: source == Int64(getpid()))
  }

  /// One key press seen by the monitor; counts only while watching, never a
  /// held-down repeat or a key WhisPaste sent itself.
  func note(flags: NSEvent.ModifierFlags, characters: String?, isRepeat: Bool, fromSelf: Bool) {
    guard monitor != nil, !isRepeat, !fromSelf else { return }
    if isUndoShortcut(flags: flags, characters: characters) { seen = true }
  }

  private func stopMonitor() {
    stopWork?.cancel()
    stopWork = nil
    if let monitor { remove(monitor) }
    monitor = nil
  }

  private func end() {
    stopMonitor()
    seen = false
  }

  var watching: Bool { monitor != nil }
}

/// Native macOS host for desktop auto-paste via CGEvent.
///
/// Captures the frontmost application before recording starts, then
/// re-activates it and sends Cmd+V to paste the transcription result.
/// Requires the user to grant Accessibility permission.
class DesktopPasteHost {
  private static let logger = OSLog(subsystem: "com.whispaste.paste", category: "DesktopPasteHost")

  private var channel: FlutterMethodChannel
  private var targetApp: NSRunningApplication?

  /// nspasteboard.org markers: clipboard managers (Maccy, Raycast, Alfred,
  /// WhisPaste's own history monitor, ...) skip items carrying them, so a
  /// dictation or its restore never lands in anyone's clipboard history.
  static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
  static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

  /// The armed receipt write (see `writeClipboardTextWithReceipt`), or nil.
  private var receipt: PasteReceipt?

  /// Full pasteboard backup taken before a dictation's paste (P1.1), or nil.
  private var clipboardSnapshot: [NSPasteboardItem]?

  /// Bounds for `snapshotClipboard`: a huge image or a slow lazy provider in
  /// another app must not stall the paste; Dart then saves plain text only.
  private static let snapshotByteLimit = 64 * 1024 * 1024
  private static let snapshotTimeBudget: Double = 1.5

  /// How long a paste without a permission signal waits for the target's
  /// read before it counts as not delivered (Mac App Store build only).
  private static let deliveryProofWindow: DispatchTimeInterval = .milliseconds(800)

  /// Monotonic time (seconds) of our last synthetic keyDown. Those events go
  /// through the HID tap too, so `inputIdleSnapshot` must not count them.
  private var lastSyntheticKeyDownAt: Double = 0

  /// Click watch of the keystroke undo (#581).
  private lazy var undoWatch = UndoWatch(clock: { [unowned self] in self.monotonicSeconds() })

  /// The user's own Cmd+Z after an auto-paste, model telemetry (#2078).
  private let undoShortcutWatch = UndoShortcutWatch()

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

    case "clipboardReadDenied":
      result(PasteboardGate.onMain { Self.clipboardReadDenied() })

    case "pasteClipboard":
      guard let args = call.arguments as? [String: Any],
            let delayMs = args["delayMs"] as? Int else {
        result(["status": "post_failed", "detail": "missing delayMs argument"])
        return
      }
      pasteClipboard(delayMs: delayMs, result: result)

    case "copySelection":
      let delayMs = (call.arguments as? [String: Any])?["delayMs"] as? Int ?? 0
      copySelection(delayMs: delayMs, result: result)

    case "typeText":
      guard let args = call.arguments as? [String: Any],
            let text = args["text"] as? String,
            let delayMs = args["delayMs"] as? Int else {
        result(["status": "post_failed", "detail": "missing text/delayMs argument"])
        return
      }
      typeText(text: text, delayMs: delayMs, result: result)

    case "writeClipboardText":
      // BIZ-61: transient copy for Undo/Selection-Edit fallbacks and restores.
      // Without this case Dart got MissingPlugin and wrote an unmarked item.
      let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
      result(PasteboardGate.onMain { writeClipboardTextExcludingHistory(text) })

    case "writeClipboardTextWithReceipt":
      let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
      result(PasteboardGate.onMain { writeClipboardTextWithReceipt(text) })

    case "waitForClipboardRead":
      PasteboardGate.onMain { waitForClipboardRead(result: result) }

    case "receiptDiagnostics":
      // Log-only facts about reads of the armed receipt (#1147).
      result(["status": "ok", "detail": receipt?.diagnostics ?? "no_receipt"])

    case "restoreClipboardTextIfOwner":
      let text = (call.arguments as? [String: Any])?["text"] as? String ?? ""
      result(["status": PasteboardGate.onMain { restoreClipboardTextIfOwner(text) }])

    case "snapshotClipboard":
      result(PasteboardGate.onMain { snapshotClipboard() })

    case "restoreClipboardSnapshotIfOwner":
      result(["status": PasteboardGate.onMain { restoreClipboardSnapshotIfOwner() }])

    case "discardClipboardSnapshot":
      clipboardSnapshot = nil
      result(nil)

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

    case "sendUndoShortcut":
      // Cmd+Z in the frontmost app: undoes a selection edit (2c, DEV-165).
      // Dart checked the contract a moment ago; the host checks again right
      // before sending and answers `sent` or why it did not (#581).
      result(sendUndoShortcut())

    case "undoPlatformSupport":
      // The keystroke-undo contract (#428, #581): answered only while the
      // click watch provably covers the span since the insert.
      let ready = undoWatch.covers
      result([
        "foregroundWindow": ready, "activateTarget": ready,
        "terminalDetection": ready, "outsideMouseIdle": ready,
      ])

    case "watchUndoShortcut":
      // Model telemetry (#2078): watch for the user's own Cmd+Z in another
      // app for {seconds} after an auto-paste; {seen} is the previous watch.
      let seconds = (call.arguments as? [String: Any])?["seconds"] as? Int ?? 0
      let start = undoShortcutWatch.watch(seconds: min(max(seconds, 0), 60))
      result(["watching": start.watching, "seen": start.seen])

    case "takeUndoShortcut":
      result(undoShortcutWatch.take())

    case "foregroundWindow":
      result(foregroundWindow())

    case "activateTarget":
      let id = (call.arguments as? [String: Any])?["id"] as? String ?? ""
      activateTarget(id: id, result: result)

    case "extraKeyHeld":
      // Auto-send (#564): is Option held right now? Sampled at hotkey release.
      result(CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate))

    case "sendEnter":
      // Auto-send (#564): Return with no modifiers, after a confirmed paste.
      result(sendReturnKey())

    case "inputIdleSnapshot":
      // DEV-185 / GS-056: raw idle ages. Dart decides (`userInputSince`).
      result(inputIdleSnapshot())

    case "secureInputState":
      // W-E1: a secure field (password, PIN) takes the keystrokes, so a
      // synthetic paste cannot land. Dart skips the paste attempt then.
      result(secureInputState())

    case "secureInputHolder":
      // F35-8: names the app holding secure input for the skipped-paste notice.
      // Only asked after a skip, never on the paste path.
      result(secureInputHolder())

    // Portal keyboard input is Linux-only (RemoteDesktop/libei). macOS keeps
    // the methods answering "unavailable" so the channel stays uniform.
    case "portalInputAvailable":
      result(false)

    case "portalInputConnect":
      result(["status": "unavailable", "restoreToken": NSNull()] as [String: Any])

    case "portalInputDisconnect":
      result(nil)

    case "destroy":
      targetApp = nil
      undoWatch.stop()
      _ = undoShortcutWatch.take()
      receipt?.resolvePending("superseded")
      receipt = nil
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
    // A new recording ends the proof of the earlier insert (#581).
    undoWatch.clearInsert()
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
  /// plan). Its answer comes from [SyntheticEventAccess], which is not just
  /// `CGPreflightPostEventAccess()`: that call stays cached within a process.
  private func canPostSyntheticEvents() -> Bool {
    SyntheticEventAccess.granted
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

#if MAS_BUILD
    // Without the delivery proof: a proof from an earlier paste says nothing
    // about this one, so it is earned again until a signal takes over.
    let trusted = SyntheticEventAccess.signals.any
#else
    let trusted = canPostSyntheticEvents()
#endif
    os_log("pasteClipboard: canPostSyntheticEvents=%{public}@ (informational — not gating)",
           log: Self.logger, type: .info, String(trusted))

    // Clamp delay to a reasonable range (0–5 seconds).
    let clampedDelay = max(0, min(delayMs, 5000))

    // Briefing B3 criterion 1: the user may have switched to another app
    // while the transcript was being processed. Pasting now would put the text
    // into an app the user did not dictate into, so refuse. The transcript
    // stays on the clipboard. Clicking WhisPaste itself is no switch away from
    // the target, so that case still pastes as before.
    if let front = NSWorkspace.shared.frontmostApplication,
       front.processIdentifier != app.processIdentifier,
       front.bundleIdentifier != Bundle.main.bundleIdentifier {
      os_log("pasteClipboard: target changed, frontmost %{public}@ is not the captured app",
             log: Self.logger, type: .info, front.bundleIdentifier ?? "<unknown>")
      result(["status": "target_changed", "detail": "frontmost app is not the captured target"])
      return
    }

    // The overlay never takes focus, so in the common dictation case the
    // target is still frontmost and has nothing to settle.
    let alreadyFrontmost = app.isActive

    // Activate the target app. macOS 14 deprecated the no-arg form in
    // favour of the options-taking variant; on older systems both exist
    // and behave identically.
    if #available(macOS 14.0, *) {
      app.activate(options: [])
    } else {
      app.activate(options: [.activateIgnoringOtherApps])
    }

    // A target that had to be brought forward gets the full delay to
    // come to front. A target that already is frontmost only waits until
    // the hotkey's modifiers are up (bounded by the same delay), so a
    // still-held Shift/Option can't turn the posted ⌘V into another
    // shortcut. Then report the real outcome to Dart.
    let bundle = app.bundleIdentifier ?? "<unknown>"
    let deadline: DispatchTime = .now() + .milliseconds(clampedDelay)
    let postPaste: () -> Void = {
      // From here on, a read of an armed receipt counts as the target's
      // paste (reads before this point are clipboard monitors).
      PasteboardGate.onMain { self.rearmReceiptIfReadEarly() }
      self.receipt?.markKeystrokePosted()
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

      let detail = "trusted=\(trusted) cg=\(cgOk) as=\(appleScriptResult) target=\(bundle) front=\(alreadyFrontmost)"
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
        // The signals can lag behind the switch while the keystroke already
        // gets through, so they cannot call this a failure on their own. The
        // target reading the transcript can tell.
        self.settleWithoutSignal(cgOk: cgOk, detail: detail, result: result)
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
    if alreadyFrontmost {
      waitForModifierRelease(until: deadline, then: postPaste)
    } else {
      DispatchQueue.main.asyncAfter(deadline: deadline, execute: postPaste)
    }
  }

#if MAS_BUILD
  /// Reports a paste no permission signal vouched for: success once the target
  /// read the armed receipt (the keystroke demonstrably got through), the
  /// missing permission otherwise. Records the answer in
  /// [SyntheticEventAccess.deliveryProven]. Polls on the main queue, which
  /// also serves the pasteboard read.
  private func settleWithoutSignal(cgOk: Bool, detail: String, result: @escaping FlutterResult) {
    let armed = cgOk ? receipt : nil
    let deadline = DispatchTime.now() + Self.deliveryProofWindow
    func poll() {
      let proven = armed?.wasRead ?? false
      if !proven, armed != nil, DispatchTime.now() < deadline {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50), execute: poll)
        return
      }
      SyntheticEventAccess.deliveryProven = proven
      os_log("pasteClipboard: no signal, delivery proven=%{public}@",
             log: Self.logger, type: .info, String(proven))
      if proven {
        result(["status": "success", "detail": detail])
      } else {
        result(["status": "no_accessibility", "detail": detail, "hint": "postevent_denied"])
      }
    }
    poll()
  }
#endif

  /// Runs [action] once no modifier key is held, or at [deadline] at the
  /// latest. Polls on the main queue, the queue [action] expects.
  private func waitForModifierRelease(
    until deadline: DispatchTime,
    then action: @escaping () -> Void
  ) {
    let modifiers: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
    let held = CGEventSource.flagsState(.combinedSessionState).intersection(modifiers)
    if held.isEmpty || DispatchTime.now() >= deadline {
      action()
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10)) {
      self.waitForModifierRelease(until: deadline, then: action)
    }
  }

  // MARK: - Receipt-based clipboard restore

  /// Plain string on the pasteboard, marked transient + concealed so clipboard
  /// managers skip it. Dart uses this for copies WhisPaste makes itself
  /// (tray recent items, selection edit, restore). Returns false when the
  /// write fails; Dart then falls back to a plain write that history records.
  private func writeClipboardTextExcludingHistory(_ text: String) -> Bool {
    receipt?.resolvePending("superseded")
    receipt = nil

    let item = NSPasteboardItem()
    guard item.setString(text, forType: .string) else { return false }
    item.setData(Data(), forType: Self.transientType)
    item.setData(Data(), forType: Self.concealedType)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.writeObjects([item]) else {
      os_log("writeClipboardText: writeObjects failed", log: Self.logger, type: .error)
      return false
    }
    return true
  }

  /// Puts [text] on the pasteboard as a *promised* item: the actual string
  /// is only handed over when a reader asks for it, which is the receipt
  /// that the target app pasted. Marked transient + concealed so clipboard
  /// managers ignore the dictation. Returns false when the item can't be
  /// written — Dart then falls back to its classic write + fixed delay.
  private func writeClipboardTextWithReceipt(_ text: String) -> Bool {
    receipt?.resolvePending("superseded")
    receipt = nil

    let provider = PasteReceiptProvider(text: text)
    let item = NSPasteboardItem()
    guard item.setDataProvider(provider, forTypes: [.string]) else { return false }
    item.setData(Data(), forType: Self.transientType)
    item.setData(Data(), forType: Self.concealedType)

    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    guard pasteboard.writeObjects([item]) else {
      os_log("writeClipboardTextWithReceipt: writeObjects failed", log: Self.logger, type: .error)
      return false
    }
    let armed = PasteReceipt(provider: provider, changeCount: pasteboard.changeCount)
    provider.onRead = { [weak self, weak armed] in
      guard let self, let armed, self.receipt === armed else { return }
      armed.handleRead()
    }
    receipt = armed
    return true
  }

  /// A reader took the promised text before the keystroke (a clipboard
  /// monitor, or the target polling on activation). The provider is asked only
  /// once, so the real paste would then yield no receipt although it landed
  /// (#1147). Writing the same text again right before the keystroke gives
  /// the paste a fresh promise; the pre-reads stay counted for the log.
  private func rearmReceiptIfReadEarly() {
    guard let old = receipt, old.preReads > 0, !old.wasRead,
          NSPasteboard.general.changeCount == old.changeCount else { return }
    let text = old.provider.text
    let earlier = old.preReads
    guard writeClipboardTextWithReceipt(text) else { return }
    receipt?.preReads = earlier
    receipt?.rearmed = true
    os_log("receipt re-armed: text was read %d time(s) before the keystroke",
           log: Self.logger, type: .info, earlier)
  }

  /// Answers once the armed receipt was read after the paste keystroke
  /// (`read`) or the pasteboard changed hands (`lost`). Otherwise the result
  /// is held until one of those happens or the receipt is superseded — Dart
  /// bounds the wait with its own timeout.
  private func waitForClipboardRead(result: @escaping FlutterResult) {
    guard let armed = receipt else {
      result(["status": "no_receipt"])
      return
    }
    if NSPasteboard.general.changeCount != armed.changeCount {
      result(["status": "lost"])
      return
    }
    armed.wait(result)
  }

  /// Restores [text] only while the pasteboard still holds our receipt
  /// write (unchanged `changeCount`) — never clobbers content another
  /// process copied in the meantime. The restore is marked transient so
  /// clipboard managers don't record WhisPaste's housekeeping either.
  private func restoreClipboardTextIfOwner(_ text: String) -> String {
    guard let armed = receipt else { return "not_owner" }
    receipt = nil
    let pasteboard = NSPasteboard.general
    guard pasteboard.changeCount == armed.changeCount else {
      armed.resolvePending("lost")
      os_log("restoreClipboardTextIfOwner: pasteboard changed — skipping", log: Self.logger, type: .info)
      return "not_owner"
    }
    armed.resolvePending("superseded")
    pasteboard.clearContents()
    let item = NSPasteboardItem()
    item.setString(text, forType: .string)
    item.setData(Data(), forType: Self.transientType)
    return pasteboard.writeObjects([item]) ? "restored" : "failed"
  }

  /// Saves every item and type on the pasteboard (image, files, RTF, HTML,
  /// ...) for the restore after the paste. The data stays here; Dart gets the
  /// status, the plain-text form (to mark the restore as its own write) and
  /// counts for the log.
  private func snapshotClipboard() -> [String: Any] {
    clipboardSnapshot = nil
    if Self.clipboardReadDenied() { return ["status": "denied"] }
    let pasteboard = NSPasteboard.general
    guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
      return ["status": "empty"]
    }
    let started = ProcessInfo.processInfo.systemUptime
    var bytes = 0
    var formats = 0
    var copies: [NSPasteboardItem] = []
    for source in items {
      let copy = NSPasteboardItem()
      for type in source.types {
        // Reading a promised type runs the owner's provider, which can be
        // slow; give up rather than hold the paste.
        if ProcessInfo.processInfo.systemUptime - started > Self.snapshotTimeBudget {
          os_log("snapshotClipboard: time budget exceeded", log: Self.logger, type: .info)
          return ["status": "failed"]
        }
        guard let data = source.data(forType: type) else { continue }
        bytes += data.count
        if bytes > Self.snapshotByteLimit {
          os_log("snapshotClipboard: content too large", log: Self.logger, type: .info)
          return ["status": "failed"]
        }
        copy.setData(data, forType: type)
        formats += 1
      }
      copies.append(copy)
    }
    if formats == 0 { return ["status": "empty"] }
    clipboardSnapshot = copies
    var result: [String: Any] = ["status": "saved", "formats": formats, "bytes": bytes]
    if let text = pasteboard.string(forType: .string) { result["text"] = text }
    return result
  }

  /// Puts the saved snapshot back under the same owner check as
  /// [restoreClipboardTextIfOwner], marked transient so clipboard managers
  /// do not record the restore as a new copy.
  private func restoreClipboardSnapshotIfOwner() -> String {
    guard let snapshot = clipboardSnapshot, !snapshot.isEmpty else { return "failed" }
    clipboardSnapshot = nil
    guard let armed = receipt else { return "not_owner" }
    receipt = nil
    let pasteboard = NSPasteboard.general
    guard pasteboard.changeCount == armed.changeCount else {
      armed.resolvePending("lost")
      os_log("restoreClipboardSnapshotIfOwner: pasteboard changed — skipping",
             log: Self.logger, type: .info)
      return "not_owner"
    }
    armed.resolvePending("superseded")
    snapshot[0].setData(Data(), forType: Self.transientType)
    pasteboard.clearContents()
    return pasteboard.writeObjects(snapshot) ? "restored" : "failed"
  }

  /// Re-activates the captured target app and sends Cmd+C so the target
  /// copies its current selection to the pasteboard ("edit selection by
  /// voice"). Dart snapshots/restores the pasteboard around this call and
  /// detects "no selection" by the pasteboard staying unchanged.
  ///
  /// Mirrors [pasteClipboard] exactly — same target, same activation, same
  /// two permission channels (CGEvent first, AppleScript only when CGEvent
  /// could not have landed; never both, which would be harmless for a copy
  /// but keeps the behavior identical). Like paste, this is available on
  /// the Mac App Store build: Cmd+C is just another CGEvent under the
  /// PostEvent grant that Cmd+V already uses there.
  private func copySelection(delayMs: Int, result: @escaping FlutterResult) {
    guard let app = targetApp else {
      os_log("copySelection: no target app — refusing", log: Self.logger, type: .error)
      result(["status": "no_target", "detail": "no target captured at copy time"])
      return
    }

    let trusted = canPostSyntheticEvents()
    let clampedDelay = max(0, min(delayMs, 5000))

    if #available(macOS 14.0, *) {
      app.activate(options: [])
    } else {
      app.activate(options: [.activateIgnoringOtherApps])
    }

    let bundle = app.bundleIdentifier ?? "<unknown>"
    let deadline: DispatchTime = .now() + .milliseconds(clampedDelay)
    DispatchQueue.main.asyncAfter(deadline: deadline) {
      let cgOk = self.sendCommandShortcut(keyCode: self.letterKeyCode("c", fallback: 0x08))
      let cgLanded = cgOk && trusted

#if MAS_BUILD
      let appleScriptResult = "unsupported"
#else
      let appleScriptResult = cgLanded
        ? "skipped"
        : self.sendCommandKeystrokeViaAppleScript(key: "c")
#endif

      let detail = "trusted=\(trusted) cg=\(cgOk) as=\(appleScriptResult) target=\(bundle)"
      os_log("copySelection: %{public}@", log: Self.logger, type: .info, detail)

      if cgLanded || appleScriptResult == "ok" {
        result(["status": "success", "detail": detail])
      } else if !trusted {
        result(["status": "no_accessibility", "detail": detail])
      } else {
        result(["status": "post_failed", "detail": detail])
      }
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
  /// Wipes the stale Accessibility TCC entry Auto-Paste depends on.
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
    // AppleEvents is deliberately not reset: its grant is independent of the
    // Accessibility entry, and re-prompting for it is an unrequested side
    // effect of "fix paste". Reported as 0 (nothing cleared) for Dart.
    result["ae"] = 0
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
    return sendCommandKeystrokeViaAppleScript(key: "v")
  }

  /// Sends Cmd+[key] via AppleScript — shared by paste (`v`) and
  /// copySelection (`c`). See [sendCmdVViaAppleScript] for the channel.
  private func sendCommandKeystrokeViaAppleScript(key: String) -> String {
#if MAS_BUILD
    // Mac App Store build: AppleEvents/Automation keystroke injection is not
    // permitted; compiled out so the shipped binary contains no NSAppleScript
    // "keystroke" payload. Never reached in practice — pasteClipboard()
    // doesn't call this under MAS_BUILD at all (see its own #if branch);
    // kept only as defense-in-depth against a careless future call site.
    return "unsupported"
#else
    let source = """
      tell application "System Events" to keystroke "\(key)" using {command down}
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
  /// permission channel [canPostSyntheticEvents] checks — and the answer
  /// carries the signals in `detail`, so the log shows which one fired. No
  /// text and nothing about the target is in there.
  private func checkCapability(prompt: Bool) -> [String: Any] {
    let trusted: Bool
#if MAS_BUILD
    let requested = prompt && CGRequestPostEventAccess()
    let signals = SyntheticEventAccess.summary
    trusted = requested || SyntheticEventAccess.granted
    os_log("checkCapability: trusted=%{public}@ prompt=%{public}@ %{public}@",
           log: Self.logger, type: .info,
           String(trusted), String(prompt), signals)
    if trusted {
      return ["status": "ready", "canPrompt": false, "detail": signals]
    }
    return ["status": "permission_missing", "canPrompt": true, "detail": signals]
#else
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
            "detail": "canPostSyntheticEvents=false"]
#endif
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
    // them back regardless of which exit path we take. A denied pasteboard
    // cannot be saved, so nothing is written at all: the clipboard stays as
    // the user left it.
    guard let backup = PasteboardGate.onMain({ self.backupPasteboard(pasteboard) }) else {
      os_log("diagnosticPaste: pasteboard access denied — nothing written",
             log: Self.logger, type: .info)
      result(["status": "clipboard_access_denied"])
      return
    }
    var restored = false
    let restore: () -> Void = {
      if restored { return }
      restored = true
      PasteboardGate.onMain { self.restorePasteboard(pasteboard, backup: backup) }
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
    PasteboardGate.onMain {
      pasteboard.clearContents()
      pasteboard.setString(demoText, forType: .string)
    }

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

  /// macOS 15.4+ pasteboard privacy: `true` when the user set WhisPaste to
  /// "always deny" programmatic access. Reads then return nothing, so a
  /// snapshot taken would be empty and must not be trusted.
  static func clipboardReadDenied() -> Bool {
    if #available(macOS 15.4, *) {
      return NSPasteboard.general.accessBehavior == .alwaysDeny
    }
    return false
  }

  /// Captures the current pasteboard items so [restorePasteboard] can put
  /// the user's clipboard back after a diagnostic paste. `nil` means the save
  /// failed (access denied): there is then nothing to restore, and nothing
  /// may be cleared either.
  private func backupPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
    if Self.clipboardReadDenied() { return nil }
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

  /// Restores a previously captured pasteboard snapshot. A `nil` snapshot
  /// (the save failed) is a no-op. An empty snapshot is not cleared either:
  /// an unreadable pasteboard also looks empty, and clearing would erase it.
  private func restorePasteboard(_ pasteboard: NSPasteboard,
                                 backup: [NSPasteboardItem]?) {
    guard let backup = backup, !backup.isEmpty else {
      os_log("restorePasteboard: no saved content — leaving the pasteboard alone",
             log: Self.logger, type: .info)
      return
    }
    pasteboard.clearContents()
    pasteboard.writeObjects(backup)
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
    undoWatch.markInsert()
    return sendCommandShortcut(keyCode: letterKeyCode("v", fallback: 0x09))
  }

  /// Keycode for a shortcut letter on the active layout (briefing N7), so
  /// Cmd+V and Cmd+C follow the letter on Dvorak and other layouts.
  private func letterKeyCode(_ letter: String, fallback: CGKeyCode) -> CGKeyCode {
    return keyCode(forCharacter: letter, layoutCharacter: activeLayoutCharacter(for:), fallback: fallback)
  }

  /// Posts Cmd+[keyCode] as a CGEvent keydown/keyup pair — shared by paste
  /// (0x09 'v') and copySelection (0x08 'c').
  /// Monotonic seconds on the same mach timebase as the HID event timestamps.
  private func monotonicSeconds() -> Double {
    Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000_000
  }

  /// Idle ages in seconds: last hardware keyDown, last left/right mouseDown
  /// (the earlier of the two), and our own last synthetic keyDown. Without a
  /// synthetic keyDown the age is a large number, so no key counts as ours.
  /// `IsSecureEventInputEnabled` (Carbon HIToolbox) is the system's own flag
  /// for secure input: set while a secure text field is focused, and while an
  /// app has asked for it. Read-only, no permission needed.
  private func secureInputState() -> String {
    IsSecureEventInputEnabled() ? "active" : "inactive"
  }

  /// The app holding secure input (F35-8). The session dictionary carries the
  /// holder's PID under `kCGSSessionSecureInputPID`; NSRunningApplication maps
  /// it to the localized name and bundle id. Nil when nobody holds the input or
  /// the PID is no running app. Reads only the session dictionary, no shell-out.
  private func secureInputHolder() -> [String: Any]? {
    guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
          let number = session["kCGSSessionSecureInputPID"] as? NSNumber,
          let app = NSRunningApplication(processIdentifier: pid_t(number.int32Value)) else {
      return nil
    }
    var holder: [String: Any] = ["pid": Int(app.processIdentifier)]
    if let name = app.localizedName, !name.isEmpty {
      holder["name"] = name
    }
    if let bundleId = app.bundleIdentifier {
      holder["bundleId"] = bundleId
    }
    return holder
  }

  private func inputIdleSnapshot() -> [String: Double] {
    let now = monotonicSeconds()
    let keyIdle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    let mouseIdle = min(
      CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown),
      CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .rightMouseDown)
    )
    let syntheticIdle = lastSyntheticKeyDownAt > 0 ? now - lastSyntheticKeyDownAt : 1e9
    var snapshot = ["keyIdle": keyIdle, "mouseIdle": mouseIdle, "syntheticIdle": syntheticIdle]
    // Without the click watch the key is missing and Dart counts every click,
    // the click on the undo action included (clipboard path).
    if undoWatch.covers {
      snapshot["mouseIdleOutsideApp"] = undoWatch.mouseIdleOutsideApp
    }
    return snapshot
  }

  /// The app with the keyboard focus now, in the vocabulary of
  /// `getTargetBundleId`. `isTerminal` means "must not get the undo key":
  /// fail-closed, only known text apps are safe ([isUndoSafeBundle]).
  private func foregroundWindow() -> [String: Any]? {
    guard let front = NSWorkspace.shared.frontmostApplication else { return nil }
    let own = front.processIdentifier == ProcessInfo.processInfo.processIdentifier ||
      front.bundleIdentifier == Bundle.main.bundleIdentifier
    guard let id = front.bundleIdentifier, !id.isEmpty else {
      // Our own window needs no readable id (it is never the target).
      return own ? ["id": "whispaste", "isOwn": true, "isTerminal": true] : nil
    }
    return ["id": id, "isOwn": own, "isTerminal": !isUndoSafeBundle(id)]
  }

  /// Brings back only the app captured for this paste, and only when its
  /// bundle id is the one Dart asks for: never an arbitrary app by name.
  /// Waits at most 500 ms for it to be in front, without blocking the UI.
  private func activateTarget(id: String, result: @escaping FlutterResult) {
    guard !id.isEmpty, let app = targetApp, !app.isTerminated,
          app.bundleIdentifier == id else {
      result(false)
      return
    }
    let inFront = {
      NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }
    // The overlay's edit field (#254) can hold the keyboard while the target
    // still counts as frontmost (a click into the non-activating panel):
    // activating the target then takes the keyboard back as well.
    let overlayHoldsKeyboard = NSApp.keyWindow is FloatingOverlayPanel
    if !inFront() || overlayHoldsKeyboard {
      if #available(macOS 14.0, *) {
        app.activate(options: [])
      } else {
        app.activate(options: [.activateIgnoringOtherApps])
      }
    }
    let started = monotonicSeconds()
    func poll() {
      if inFront() {
        result(true)
      } else if monotonicSeconds() - started >= 0.5 {
        result(false)
      } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(10), execute: poll)
      }
    }
    poll()
  }

  /// The last check right before Cmd+Z (#581): the app in front is still the
  /// paste target and a safe one, and since the insert the watch saw no key
  /// and no click outside WhisPaste. Answers `sent` or why nothing was sent.
  private func sendUndoShortcut() -> String {
    let now = monotonicSeconds()
    let front = NSWorkspace.shared.frontmostApplication
    let check = decideUndoSend(
      targetBundle: targetApp?.bundleIdentifier,
      frontIsTarget: front != nil && targetApp?.isTerminated == false
        && front?.processIdentifier == targetApp?.processIdentifier,
      covers: undoWatch.covers,
      sinceInsert: undoWatch.sinceInsert,
      keyIdle: CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown),
      syntheticIdle: lastSyntheticKeyDownAt > 0 ? now - lastSyntheticKeyDownAt : 1e9,
      mouseIdleOutsideApp: undoWatch.mouseIdleOutsideApp
    )
    if check != .send { return check.rawValue }
    // One insert, one undo: a second call must not press the key again.
    undoWatch.clearInsert()
    return sendCommandShortcut(keyCode: letterKeyCode("z", fallback: 0x06)) ? "sent" : "send_failed"
  }

  /// Posts a plain Return keydown/keyup. Flags are cleared explicitly so a
  /// still-held Option does not turn it into Option+Return (#564).
  private func sendReturnKey() -> Bool {
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0x24, keyDown: false) else {
      return false
    }
    keyDown.flags = []
    keyUp.flags = []
    lastSyntheticKeyDownAt = monotonicSeconds()
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }

  private func sendCommandShortcut(keyCode: CGKeyCode) -> Bool {
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
      return false
    }

    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand

    lastSyntheticKeyDownAt = monotonicSeconds()
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
    undoWatch.clearInsert() // typed text has no undo by key (#581)
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
      lastSyntheticKeyDownAt = monotonicSeconds()
      keyDown.post(tap: .cghidEventTap)
      usleep(interEventDelayUs)
      keyUp.post(tap: .cghidEventTap)
      usleep(isLastChunk ? finalFlushDelayUs : interEventDelayUs)

      index = end
    }
    return true
  }
}

/// State of one receipt write — lives on the main thread only (method
/// channel handler and pasteboard provider callbacks both run there).
private final class PasteReceipt {
  let provider: PasteReceiptProvider
  let changeCount: Int
  private(set) var keystrokePosted = false
  /// Reads before the keystroke (monitors; not proof of the paste).
  var preReads = 0
  var rearmed = false
  private var keystrokeAt: Date?
  private var firstReadAfterMs: Int?
  private var read = false
  /// The target read the transcript after the paste keystroke.
  var wasRead: Bool { read }
  private var pending: FlutterResult?

  init(provider: PasteReceiptProvider, changeCount: Int) {
    self.provider = provider
    self.changeCount = changeCount
  }

  /// Only reads after the paste keystroke count — an earlier read is a
  /// clipboard monitor, and since the provider is consulted once, the real
  /// paste then yields no receipt and Dart falls back to its fixed delay.
  func markKeystrokePosted() {
    keystrokePosted = true
    keystrokeAt = Date()
  }

  /// Log-only summary: reads before the keystroke and the first read after it.
  var diagnostics: String {
    let after = firstReadAfterMs.map { "\($0)ms" } ?? "none"
    return "preReads=\(preReads) firstReadAfterKey=\(after) rearmed=\(rearmed)"
  }

  func handleRead() {
    guard keystrokePosted else {
      preReads += 1
      return
    }
    if firstReadAfterMs == nil, let at = keystrokeAt {
      firstReadAfterMs = Int(Date().timeIntervalSince(at) * 1000)
    }
    read = true
    resolvePending("read")
  }

  func wait(_ result: @escaping FlutterResult) {
    if read {
      result(["status": "read"])
      return
    }
    resolvePending("superseded")
    pending = result
  }

  func resolvePending(_ status: String) {
    pending?(["status": status])
    pending = nil
  }
}

/// Lazily hands the transcript to whichever process reads the pasteboard
/// and reports that read.
private final class PasteReceiptProvider: NSObject, NSPasteboardItemDataProvider {
  let text: String
  var onRead: (() -> Void)?

  init(text: String) {
    self.text = text
  }

  func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                  provideDataForType type: NSPasteboard.PasteboardType) {
    guard type == .string else { return }
    item.setString(text, forType: .string)
    onRead?()
  }
}

/// Whether this build may post synthetic keystrokes right now.
///
/// Developer-ID build: `AXIsProcessTrusted()`, which updates live.
///
/// Mac App Store build: the grant is the `PostEvent` TCC service. Its own
/// check, `CGPreflightPostEventAccess()`, stays cached within a process: after
/// the user flips the switch it keeps reading `false` until a relaunch, while
/// posted keystrokes already arrive. So it is one signal of three, and any one
/// of them counts:
///   - `pre`: `CGPreflightPostEventAccess()`, exact from the next launch on.
///   - `ax`: `AXIsProcessTrusted()`. Usually `false` in the sandbox, but System
///     Settings shows PostEvent and Accessibility as one switch, so `true`
///     means that switch is on.
///   - `hid`: `IOHIDCheckAccess(kIOHIDRequestTypePostEvent)`, a public call
///     with its own TCC read outside the CoreGraphics cache; it never prompts.
/// The fourth way in is [deliveryProven]: a target read a paste that no signal
/// vouched for. Which signals fire live is in the log of every capability
/// check ([summary]).
enum SyntheticEventAccess {
  struct Signals {
    let preflight: Bool
    let accessibility: Bool
    let hid: Bool

    var any: Bool { preflight || accessibility || hid }
  }

  /// The three OS signals, read fresh. Mac App Store build only in effect; the
  /// Developer-ID build reads just `AXIsProcessTrusted()` through [granted].
  static var signals: Signals {
    Signals(
      preflight: CGPreflightPostEventAccess(),
      accessibility: AXIsProcessTrusted(),
      hid: IOHIDCheckAccess(kIOHIDRequestTypePostEvent) == kIOHIDAccessTypeGranted
    )
  }

  /// Set when a paste without any signal reached its target, cleared when the
  /// next such paste did not. Main queue only.
  static var deliveryProven = false

  static var granted: Bool {
#if MAS_BUILD
    return signals.any || deliveryProven
#else
    return AXIsProcessTrusted()
#endif
  }

  /// The signals for the log, e.g. `pre=false ax=false hid=true proven=false`.
  static var summary: String {
    let now = signals
    return "pre=\(now.preflight) ax=\(now.accessibility) hid=\(now.hid) proven=\(deliveryProven)"
  }
}
