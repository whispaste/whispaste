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
  init(width: CGFloat = 346, height: CGFloat = 80) {
    let rect = NSRect(x: 100, y: 100, width: width, height: height)
    super.init(
      contentRect: rect,
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
