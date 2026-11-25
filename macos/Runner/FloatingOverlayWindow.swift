import Cocoa
import FlutterMacOS

/// NSPanel subclass for the floating overlay — non-activating, always-on-top.
///
/// ADR 0002 (Approach 1 / Variant B): this is a lifecycle-only shell. It holds
/// a `FlutterViewController` (the dedicated overlay render engine) and does no
/// drawing itself — the shared Dart `FloatingOverlayView` paints every pixel.
/// Empirical spike finding: only an `NSPanel` (not a plain `NSWindow`) stays
/// reliably above fullscreen spaces.
///
/// The content size is set by `FloatingOverlayHost` to the exact
/// `OverlayDesignSpec.windowSize` (pill box + 8pt shadow padding per side), so
/// the painted soft shadow is never clipped.
class FloatingOverlayPanel: NSPanel {
  /// Floor for the shell's frame, set by the host to the current size class
  /// (`FloatingOverlayHost.contentSize()`) before the render view is attached.
  ///
  /// OVERLAY-BACKING-STORE: AppKit can collapse an ordered-out panel to 0x0
  /// (observed 2026-10-26: `resizePanelToContent ... panel.isVisible=false,
  /// frame=(0,0,0,0)`). A 0x0 render surface has no backing store, so the
  /// embedder fails on every frame and logs it at frame rate. The floor keeps
  /// the surface at a valid size whatever AppKit tries to adopt.
  var minimumFrameSize: NSSize

  init(width: CGFloat = 346, height: CGFloat = 80) {
    let rect = NSRect(x: 100, y: 100, width: width, height: height)
    minimumFrameSize = NSSize(width: width, height: height)
    super.init(
      contentRect: rect,
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

  override func setFrame(_ frameRect: NSRect, display flag: Bool) {
    super.setFrame(Self.clamped(frameRect, minimum: minimumFrameSize), display: flag)
  }

  override func setContentSize(_ size: NSSize) {
    super.setContentSize(
      NSSize(
        width: max(size.width, minimumFrameSize.width),
        height: max(size.height, minimumFrameSize.height)
      )
    )
  }

  /// Raises each dimension of `rect` to at least `minimum`; the origin is kept.
  static func clamped(_ rect: NSRect, minimum: NSSize) -> NSRect {
    NSRect(
      x: rect.origin.x,
      y: rect.origin.y,
      width: max(rect.width, minimum.width),
      height: max(rect.height, minimum.height)
    )
  }

  /// Whether the panel may take the keyboard. Only during an edit session of
  /// the write preview (#254): the host turns it on while the card's edit
  /// field is open and off again when the field goes. Outside of that the
  /// overlay never takes focus from the target app.
  var acceptsKeyboard = false

  override var canBecomeKey: Bool { acceptsKeyboard }
  override var canBecomeMain: Bool { false }

  /// Not a dialog: the overlay is a floating status window (#1923).
  override func accessibilitySubrole() -> NSAccessibility.Subrole? { .floatingWindow }
}
