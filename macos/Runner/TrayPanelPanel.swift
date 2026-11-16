import Cocoa

/// Borderless, non-activating panel of the tray / menu bar panel (#920).
///
/// `.nonactivatingPanel` lets it become key (Escape, Tab, Space/Return reach
/// the Flutter view) without activating WhisPaste, so
/// `NSWorkspace.frontmostApplication` stays the app the user is writing in
/// and `DesktopPasteHost.captureTarget()` keeps the paste target. Never
/// `canBecomeMain`.
class TrayPanelPanel: NSPanel {
  init(contentSize: NSSize) {
    super.init(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    isOpaque = false
    backgroundColor = .clear
    // The Flutter body draws the floating shadow.
    hasShadow = false
    isMovableByWindowBackground = false
    hidesOnDeactivate = false
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
