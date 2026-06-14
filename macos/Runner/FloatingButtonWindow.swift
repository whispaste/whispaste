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
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false // The Flutter painter renders its own soft shadow.
    isMovableByWindowBackground = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}
