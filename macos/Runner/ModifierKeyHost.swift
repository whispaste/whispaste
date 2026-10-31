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
      result(["listenAccess": CGPreflightListenEventAccess()])

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

    case "stop":
      stop()
      result(nil)

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
    return true
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
  }

  /// Runs on the main run loop, where the channel may be called.
  private func handleTap(type: CGEventType, event: CGEvent) {
    // The system disables a slow or input-blocked tap. Turn it back on, then
    // read the real key state: presses or releases that happened while the
    // tap was off would otherwise leave isDown wrong for good.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
      resyncWatchedKey()
      return
    }
    guard let key = watched else { return }

    if type == .keyDown {
      // Only a press while the watched key is held can matter to the gesture
      // layer; every other key is ignored here (performance: no channel call
      // for ordinary typing).
      if isDown {
        channel.invokeMethod("event", arguments: ["type": "other"])
      }
      return
    }

    guard type == .flagsChanged else { return }
    guard event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else {
      // Another modifier while the watched one is held (⇧ + ⌘ …) makes the
      // press a chord, not a gesture.
      if isDown {
        channel.invokeMethod("event", arguments: ["type": "other"])
      }
      return
    }
    // The event's own flags say whether the key is down now. Taking this per
    // event (not toggling) keeps the state right after a lost event.
    let nowDown = key.isDown(in: event.flags)
    guard nowDown != isDown else { return }
    isDown = nowDown
    channel.invokeMethod("event", arguments: ["type": nowDown ? "down" : "up"])
  }

  /// Brings isDown in line with the hardware after the tap was re-enabled. A
  /// release that was missed is reported as `up`, which ends a hold. A press
  /// that was missed is not reported, because a hold cannot start from a
  /// stale state; its release then arrives as a no-op `up` on the Dart side.
  private func resyncWatchedKey() {
    guard let key = watched else { return }
    let actual = CGEventSource.keyState(
      .combinedSessionState,
      key: CGKeyCode(key.keyCode)
    )
    guard actual != isDown else { return }
    isDown = actual
    if !actual {
      channel.invokeMethod("event", arguments: ["type": "up"])
    }
  }
}
