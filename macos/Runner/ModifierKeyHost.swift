import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

/// Observes a single modifier-only hotkey (right Control, right Alt/Option,
/// right Meta/Command or Fn/Globe) for the Dart hotkey layer.
///
/// One path for every build (Developer ID and Mac App Store): a listen-only
/// `CGEventTap` on `flagsChanged` and `keyDown`. It needs the Input Monitoring
/// grant (`CGPreflightListenEventAccess`), not Accessibility. The grant is
/// requested only through `requestListenAccess`, which Dart calls after the
/// user has chosen a modifier gesture and read the explanation.
///
/// Apple's `CGEvent.tapCreate` documentation (legacy text) names root or
/// enabled Accessibility as the requirement for key events. The Input
/// Monitoring path is therefore not confirmed by the docs read so far. It is
/// to be verified on the Mac App Store build (plan item 16a). If the tap
/// cannot be created, `start` reports `tap_failed` and Dart keeps the normal
/// key combination.
///
/// The host forwards raw events only: `down` / `up` for the watched key and
/// `other` for any key pressed while it is observed. Gesture decisions stay in
/// `HotkeyGestureMachine` on the Dart side.
final class ModifierKeyHost {
  private let channel: FlutterMethodChannel
  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var watched: WatchedKey?
  private var isDown = false
  /// When the watched key went down, from the event itself (seconds since
  /// startup). Nil when the press was not seen, e.g. after a resync.
  private var downAt: TimeInterval?
  /// Whether `other` was already sent for the current press, so the
  /// secure-input check on release does not send it twice.
  private var otherSent = false
  /// Times the system disabled the tap since `start` (#848), and when the
  /// last one happened (`ProcessInfo.systemUptime`). Counters only, never
  /// key data; Dart writes them to the app log.
  private var disabledCount = 0
  private var lastDisabledAt: TimeInterval?

  /// Virtual key codes from Carbon's `HIToolbox/Events.h` (kVK_Shift,
  /// kVK_RightShift, kVK_Control, kVK_RightControl, kVK_Option,
  /// kVK_RightOption, kVK_Command, kVK_RightCommand, kVK_Function). Verify on
  /// hardware. Names are shared with the Windows and Linux hosts (`*Meta` is
  /// Command here, Win on Windows, Super on Linux).
  private enum WatchedKey: String {
    case fn
    case leftShift
    case rightShift
    case leftControl
    case rightControl
    case leftAlt
    case rightAlt
    case leftMeta
    case rightMeta

    var keyCode: Int64 {
      switch self {
      case .fn: return 63
      case .leftShift: return 56
      case .rightShift: return 60
      case .leftControl: return 59
      case .rightControl: return 62
      case .leftAlt: return 58
      case .rightAlt: return 61
      case .leftMeta: return 55
      case .rightMeta: return 54
      }
    }

    /// Whether [flags] show this key down. Each side of a modifier has its
    /// own device-dependent bit (IOKit NX_DEVICELCTLKEYMASK 0x1, LSHIFT 0x2,
    /// RSHIFT 0x4, LCMD 0x8, RCMD 0x10, LALT 0x20, RALT 0x40, RCTL 0x2000), so
    /// the left and the right key are told apart. Fn has no side and uses
    /// maskSecondaryFn.
    func isDown(in flags: CGEventFlags) -> Bool {
      switch self {
      case .fn: return flags.contains(.maskSecondaryFn)
      case .leftShift: return flags.rawValue & 0x2 != 0
      case .rightShift: return flags.rawValue & 0x4 != 0
      case .leftControl: return flags.rawValue & 0x1 != 0
      case .rightControl: return flags.rawValue & 0x2000 != 0
      case .leftAlt: return flags.rawValue & 0x20 != 0
      case .rightAlt: return flags.rawValue & 0x40 != 0
      case .leftMeta: return flags.rawValue & 0x8 != 0
      case .rightMeta: return flags.rawValue & 0x10 != 0
      }
    }
  }

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.whispaste.modifier_monitor",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler(handle)
  }

  deinit {
    stop()
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      // `tapActive` only while a key is watched (#836): the system disabled
      // or invalidated the tap behind our back when it is false. Dart asks
      // every few seconds and rebuilds through `start` on a dead tap.
      var reply: [String: Any] = ["listenAccess": CGPreflightListenEventAccess()]
      if watched != nil {
        reply["tapActive"] = isTapAlive()
      }
      result(reply)

    case "requestListenAccess":
      // Shows the system prompt; the reply is the state right now.
      result(CGRequestListenEventAccess())

    case "start":
      guard CGPreflightListenEventAccess() else {
        result(FlutterError(code: "UNSUPPORTED", message: "no_input_monitoring", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let raw = args["key"] as? String,
            let key = WatchedKey(rawValue: raw) else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing or unknown 'key'", details: nil))
        return
      }
      if start(key) {
        result(true)
      } else {
        result(FlutterError(code: "UNSUPPORTED", message: "tap_failed", details: nil))
      }

    case "isHeld":
      // The hardware state of the watched key, for the lost-release check
      // (#791). The main key of a registered combination arrives as
      // `keyCode`; without it the observed modifier is read. Nil when
      // nothing is watched. Without the Input Monitoring grant the system may
      // report keys of other apps as up, and a false "up" would end a running
      // hold; nil keeps the release event as the only signal then.
      guard CGPreflightListenEventAccess() else {
        result(nil)
        return
      }
      let args = call.arguments as? [String: Any]
      if let code = args?["keyCode"] as? Int, code >= 0, code <= 0xFFFF {
        result(CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(code)))
      } else if let key = watched {
        // Same source as the event path: the device-specific modifier bits,
        // so the left and the right key are told apart.
        result(key.isDown(in: CGEventSource.flagsState(.combinedSessionState)))
      } else {
        result(nil)
      }

    case "inputDisturbance":
      // #775: read once after a hotkey press, off the trigger path. Notice
      // only: nothing here changes another app or its tap.
      result(inputDisturbance())

    case "stop":
      stop()
      result(nil)

    case "globeKeyAction":
      // #778: the system setting "Press 🌐 key to" (com.apple.HIToolbox
      // AppleFnUsageType: 0 none, 1 input source, 2 emoji, 3 dictation).
      // Read only, never written: the user's choice stays untouched. nil =
      // key absent = system default. Readable inside the App Sandbox
      // (checked 2026-11-10 with a sandboxed, ad-hoc signed probe).
      let raw = CFPreferencesCopyAppValue(
        "AppleFnUsageType" as CFString, "com.apple.HIToolbox" as CFString)
      result((raw as? NSNumber)?.intValue)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(_ key: WatchedKey) -> Bool {
    stop()
    let mask: CGEventMask =
      (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
    let refcon = Unmanaged.passUnretained(self).toOpaque()
    guard let newTap = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .listenOnly,
      eventsOfInterest: mask,
      callback: { _, type, event, refcon in
        if let refcon = refcon {
          Unmanaged<ModifierKeyHost>.fromOpaque(refcon)
            .takeUnretainedValue()
            .handleTap(type: type, event: event)
        }
        return Unmanaged.passUnretained(event)
      },
      userInfo: refcon
    ) else {
      return false
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: newTap, enable: true)
    tap = newTap
    runLoopSource = source
    watched = key
    isDown = false
    downAt = nil
    disabledCount = 0
    lastDisabledAt = nil
    return true
  }

  /// Whether the tap exists, is valid and enabled right now (#836).
  private func isTapAlive() -> Bool {
    guard let tap = tap else { return false }
    return CFMachPortIsValid(tap) && CGEvent.tapIsEnabled(tap: tap)
  }

  private func stop() {
    if let source = runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
    }
    if let tap = tap {
      CGEvent.tapEnable(tap: tap, enable: false)
    }
    runLoopSource = nil
    tap = nil
    watched = nil
    isDown = false
    downAt = nil
  }

  /// Runs on the main run loop, where the channel may be called.
  private func handleTap(type: CGEventType, event: CGEvent) {
    // The system disables a slow or input-blocked tap. Turn it back on, then
    // read the real key state: presses or releases that happened while the
    // tap was off would otherwise leave isDown wrong for good.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
      reportTapDisabled(byTimeout: type == .tapDisabledByTimeout)
      resyncWatchedKey()
      return
    }
    guard let key = watched else { return }

    if type == .keyDown {
      // Only a press while the watched key is held can matter to the gesture
      // layer; every other key is ignored here (performance: no channel call
      // for ordinary typing).
      if isDown {
        sendOther()
      }
      return
    }

    guard type == .flagsChanged else { return }
    guard event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else {
      // Another modifier while the watched one is held (⇧ + ⌘ …) makes the
      // press a chord, not a gesture.
      if isDown {
        sendOther()
      }
      return
    }
    // The event's own flags say whether the key is down now. Taking this per
    // event (not toggling) keeps the state right after a lost event.
    let nowDown = key.isDown(in: event.flags)
    guard nowDown != isDown else { return }
    isDown = nowDown
    // The press length comes from the events' own timestamps, so a busy main
    // thread does not shorten it (F15-4). NSEvent gives seconds on every Mac;
    // the raw CGEvent timestamp is in host ticks on Apple silicon.
    let at = NSEvent(cgEvent: event)?.timestamp
    // The event's own time on the monotonic boot clock, as a growing
    // millisecond stamp: Dart decides hold, tap and double tap from these, so
    // a stalled main thread cannot turn a hold into a tap (issue #787).
    var stamp: [String: Any] = [:]
    if let at = at, at >= 0 {
      stamp["atMs"] = Int((at * 1000).rounded())
    }
    if nowDown {
      downAt = at
      otherSent = false
      var args = stamp
      args["type"] = "down"
      channel.invokeMethod("event", arguments: args)
      return
    }
    // #775: under secure input the system hands no keyDown to the tap, so
    // ⌘ + a key in a password field would look like a clean tap or hold.
    // The HID idle age of the last keyDown still moves; a keyDown newer than
    // the press start makes it a chord, sent as `other` before the release.
    // Verify on hardware.
    if !otherSent, IsSecureEventInputEnabled(), let start = downAt,
       keyDownSince(start) {
      sendOther()
    }
    var args = stamp
    args["type"] = "up"
    if let start = downAt, let end = at, end >= start, end - start <= 60 {
      args["pressMs"] = Int(((end - start) * 1000).rounded())
    }
    downAt = nil
    channel.invokeMethod("event", arguments: args)
  }

  /// #848: tells Dart that the system disabled the tap and it was enabled
  /// again, with the running count and the gap to the previous one. State
  /// only; Dart throttles what reaches the log.
  private func reportTapDisabled(byTimeout: Bool) {
    let now = ProcessInfo.processInfo.systemUptime
    disabledCount += 1
    var args: [String: Any] = [
      "type": "tapDisabled",
      "reason": byTimeout ? "timeout" : "userInput",
      "count": disabledCount,
    ]
    if let last = lastDisabledAt {
      args["sinceLastMs"] = Int(((now - last) * 1000).rounded())
    }
    lastDisabledAt = now
    channel.invokeMethod("event", arguments: args)
  }

  private func sendOther() {
    otherSent = true
    channel.invokeMethod("event", arguments: ["type": "other"])
  }

  /// Whether a non-modifier key went down after [start] (NSEvent seconds
  /// since boot, same clock as `ProcessInfo.systemUptime`).
  private func keyDownSince(_ start: TimeInterval) -> Bool {
    let held = ProcessInfo.processInfo.systemUptime - start
    guard held > 0 else { return false }
    let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    return idle < held
  }

  /// Secure input with its holder, and other apps' active keyboard taps with
  /// their average latency (#775). Public APIs only: `IsSecureEventInputEnabled`,
  /// the session dictionary (`kCGSSessionSecureInputPID`) and
  /// `CGGetEventTapList`. In the Mac App Store sandbox a lookup may come back
  /// empty; the answer then simply lacks the holder or the taps. Dart picks
  /// the notice and the latency threshold.
  private func inputDisturbance() -> [String: Any] {
    var answer: [String: Any] = ["secureInput": IsSecureEventInputEnabled()]
    if IsSecureEventInputEnabled(),
       let session = CGSessionCopyCurrentDictionary() as? [String: Any],
       let number = session["kCGSSessionSecureInputPID"] as? NSNumber {
      answer["holder"] = Self.describe(pid: pid_t(number.int32Value))
    }
    answer["keyboardTaps"] = otherKeyboardTaps()
    return answer
  }

  private static func describe(pid: pid_t) -> [String: Any] {
    var info: [String: Any] = ["pid": Int(pid)]
    if let app = NSRunningApplication(processIdentifier: pid) {
      if let name = app.localizedName, !name.isEmpty { info["name"] = name }
      if let bundleId = app.bundleIdentifier { info["bundleId"] = bundleId }
    }
    return info
  }

  /// Enabled, filtering (not listen-only) taps of other processes that see
  /// key presses. Only those can hold a key event back.
  private func otherKeyboardTaps() -> [[String: Any]] {
    var count: UInt32 = 0
    guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return [] }
    var list = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
    guard CGGetEventTapList(count, &list, &count) == .success else { return [] }
    let ownPid = ProcessInfo.processInfo.processIdentifier
    let keyMask: CGEventMask =
      (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    var taps: [[String: Any]] = []
    for tap in list.prefix(Int(count)) {
      guard tap.enabled, tap.options == .defaultTap,
            tap.eventsOfInterest & keyMask != 0,
            tap.tappingProcess != ownPid else { continue }
      var info = Self.describe(pid: tap.tappingProcess)
      info["avgLatencyUs"] = Double(tap.avgUsecLatency)
      taps.append(info)
    }
    return taps
  }

  /// Brings isDown in line with the hardware after the tap was re-enabled. A
  /// release that was missed is reported as `up`, which ends a hold. A press
  /// that was missed is not reported, because a hold cannot start from a
  /// stale state; its release then arrives as a no-op `up` on the Dart side.
  private func resyncWatchedKey() {
    guard let key = watched else { return }
    let actual = key.isDown(in: CGEventSource.flagsState(.combinedSessionState))
    guard actual != isDown else { return }
    isDown = actual
    downAt = nil
    if !actual {
      channel.invokeMethod("event", arguments: ["type": "up"])
    }
  }
}
