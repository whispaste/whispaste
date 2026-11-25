import Cocoa
import FlutterMacOS

/// Reports the system setting "Reduce motion" to every Flutter engine (#1756).
///
/// The macOS embedder does not set `AccessibilityFeatures.disableAnimations`,
/// so `MediaQuery.disableAnimations` stayed false although the user asked the
/// system for less motion. Each engine (main window, floating overlay,
/// floating button, tray panel, side panel, snippet picker) calls [attach]
/// with its messenger; Dart reads the current value with `reduceMotion` and
/// gets `reduceMotionChanged` whenever the setting flips at runtime. The Dart
/// side (`lib/core/accessibility/system_motion.dart`) folds it into
/// `MediaQuery`.
///
/// Messengers are held weakly: an engine that is torn down (boot-race retry)
/// simply drops out of the broadcast.
final class SystemMotionHost {
  static let channelName = "com.whispaste.system_motion"
  static let shared = SystemMotionHost()

  private let messengers = NSHashTable<AnyObject>.weakObjects()
  private var observer: NSObjectProtocol?

  private init() {}

  static var reduceMotion: Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
  }

  /// Registers the channel on [messenger]. Call once per engine, right after
  /// the engine is created.
  static func attach(_ messenger: FlutterBinaryMessenger) {
    shared.attach(messenger)
  }

  private func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "reduceMotion":
        result(Self.reduceMotion)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    messengers.add(messenger as AnyObject)
    startObservingIfNeeded()
  }

  private func startObservingIfNeeded() {
    guard observer == nil else { return }
    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.broadcast()
    }
  }

  private func broadcast() {
    let value = Self.reduceMotion
    for case let messenger as FlutterBinaryMessenger in messengers.allObjects {
      FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        .invokeMethod("reduceMotionChanged", arguments: value)
    }
  }
}
