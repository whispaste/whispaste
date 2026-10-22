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

  /// Virtual key codes from Carbon's `HIToolbox/Events.h` (kVK_RightControl,
  /// kVK_RightOption, kVK_RightCommand, kVK_Function). Verify on hardware.
  /// Names are shared with the Windows and Linux hosts (`rightMeta` is Command
  /// here, Win on Windows, Super on Linux).
  private enum WatchedKey: String {
    case rightControl
    case rightAlt
    case rightMeta
    case fn

    var keyCode: Int64 {
      switch self {
      case .rightControl: return 62
      case .rightAlt: return 61
      case .rightMeta: return 54
      case .fn: return 63
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
    // The system disables a slow tap; turn it back on so the hotkey keeps working.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return
    }
    guard let key = watched else { return }

    if type == .keyDown {
      channel.invokeMethod("event", arguments: ["type": "other"])
      return
    }

    // Each flagsChanged for the watched key is one press or one release, so
    // toggling a local flag avoids reading the shared modifier mask, where a
    // left key of the same kind would also show up.
    guard type == .flagsChanged,
          event.getIntegerValueField(.keyboardEventKeycode) == key.keyCode else { return }
    isDown.toggle()
    channel.invokeMethod("event", arguments: ["type": isDown ? "down" : "up"])
  }
}
