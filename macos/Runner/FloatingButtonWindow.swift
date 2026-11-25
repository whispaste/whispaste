import Cocoa

/// NSPanel subclass for the floating button — non-activating, always-on-top.
///
/// ADR 0002 (Approach 1 / Variant B): this is a lifecycle-only shell. It holds
/// a `FlutterViewController` (the dedicated button render engine) and does no
/// drawing itself — the shared Dart `FloatingButtonView` paints every pixel.
/// Empirical spike finding: only an `NSPanel` (not a plain `NSWindow`) stays
/// reliably above fullscreen spaces.
///
/// The content size is set by `FloatingButtonHost` to the exact
/// `OverlayDesignSpec.buttonWindowSize` (disc + 8pt shadow padding per side),
/// so the painted soft shadow is never clipped.
class FloatingButtonPanel: NSPanel {
  init(size: CGFloat) {
    let frame = NSRect(x: 200, y: 200, width: size, height: size)
    super.init(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .floating
    // NSPanel defaults to true: the panel would leave the screen as soon as
    // WhisPaste loses activation, for example mid-dictation (#484).
    hidesOnDeactivate = false
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false // The Flutter painter renders its own soft shadow.
    isMovableByWindowBackground = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  /// A borderless non-activating panel reads as AXSystemDialog; the button is
  /// a floating tool window, not a dialog (#1923).
  override func accessibilitySubrole() -> NSAccessibility.Subrole? { .floatingWindow }
}

/// Semantics for the secondary render engines (#1923).
///
/// The macOS embedder turns an engine's semantics on only when AppKit posts
/// its private "enhanced user interface" notification, which happens when
/// VoiceOver or another assistive client attaches to the app. The floating
/// button, overlay, side panel, picker and tray panel engines start later, so
/// they never heard it: their windows showed one unnamed group and no button.
/// This remembers the last state AppKit announced and replays it to an engine
/// once its view controller exists. Posting with the current state is a no-op
/// for engines that already have it.
enum RenderEngineAccessibility {
  private static let notification = Notification.Name(
    "NSApplicationDidChangeAccessibilityEnhancedUserInterfaceNotification")
  private static let key = "AXEnhancedUserInterface"
  private static var enhanced = NSWorkspace.shared.isVoiceOverEnabled
  private static var observer: NSObjectProtocol?

  /// Starts tracking AppKit's state; call once at launch.
  static func start() {
    guard observer == nil else { return }
    observer = NotificationCenter.default.addObserver(
      forName: notification, object: nil, queue: .main
    ) { note in
      if let value = note.userInfo?[key] as? Bool { enhanced = value }
    }
  }

  /// Hands the current state to engines started after AppKit announced it.
  static func replayToNewEngine() {
    guard enhanced else { return }
    NotificationCenter.default.post(name: notification, object: nil, userInfo: [key: true])
  }
}
