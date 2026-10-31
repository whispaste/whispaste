import Cocoa

/// NSPanel subclass for the Snippet-Picker (dictation-automations ticket 06)
/// — non-activating, but (unlike `FloatingButtonPanel`/`FloatingOverlayWindow`)
/// *can* become key so its search field receives real keystrokes.
///
/// `.nonactivatingPanel` is the load-bearing style here: AppKit lets a panel
/// with this mask become the key window (accepting keyboard input) WITHOUT
/// activating its owning application — `NSWorkspace.shared.frontmostApplication`
/// stays whatever app was frontmost before this panel opened. That's the
/// mechanism ticket 06 leans on to keep the previously captured paste target
/// intact while this panel holds keyboard focus for search (see
/// `DesktopPasteHost.captureTarget()` — it destructively clears the stored
/// target whenever WhisPaste itself is frontmost, so this panel must never
/// cause that to become true).
class SnippetPickerPanel: NSPanel {
  init(contentSize: NSSize) {
    let frame = NSRect(origin: .zero, size: contentSize)
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
    hasShadow = true
    isMovableByWindowBackground = false
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}
