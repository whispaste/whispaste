import Cocoa
import FlutterMacOS

/// NSPanel subclass hosting the side-panel's own second Flutter engine.
///
/// `.nonactivatingPanel`, always-on-top -- exactly like `FloatingOverlayPanel`
/// (issue 04 ticket: "WhisPaste darf beim Panel-Öffnen nicht selbst zum
/// Frontmost-Prozess werden, sonst liefert `captureTarget()` kein gültiges
/// Ziel mehr"). Lifecycle-only shell; `WpSidePanelView` paints every pixel.
///
/// [canBecomeKey] is `true` (issue 09) so the search field can hold key
/// status -- same precedent as `SnippetPickerPanel`. That alone does not
/// make the field typeable: macOS routes physical keystrokes to the
/// *active application*, not merely to the key window of an inactive one,
/// so `SidePanelHost.slideIn` also activates WhisPaste once the panel is on
/// screen (see `SidePanelHost.activateForKeyboard`) and restores whichever
/// app was previously frontmost once the panel slides back out (see
/// `SidePanelHost.restorePreviousFrontApp`) -- the paste-target-capture
/// invariant above only needs to hold at the *next* `prime()`, not while
/// the panel itself is open, since the current paste target was already
/// captured in `SidePanelService.open()` before this panel took focus.
class SidePanelContentPanel: NSPanel {
  init(frame: NSRect) {
    super.init(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    // Matches SidePanelSensorPanel's level -- keeps both panels above any
    // known screen-covering utility overlay (e.g. window-snap tools like
    // Magnet, observed at CGWindowLevel 25) rather than `.floating`'s 3.
    // Not itself the cause of the "reagiert nicht mehr"/"kein Feedback"
    // reports (those turned out to be the `NSApp.isActive` race in
    // `activateForKeyboard` and a stale-frame display-link bug in
    // `slideIn`, both fixed in SidePanelHost.swift), kept as a precaution
    // for the input-swallowing failure mode it does address.
    level = .popUpMenu
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    // A native window shadow renders past this borderless panel's own frame
    // on every edge, including the top edge against the menu bar and the
    // left edge against the screen border where the desktop is still visible
    // behind it -- it reads as a grey halo/frame around the whole panel
    // rather than the intended flush-left, floating-right card.
    hasShadow = false
    isMovableByWindowBackground = false
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// Thin, transparent, always-on-top, non-activating `NSPanel` hugging the
/// left edge of one monitor -- the "edge sensor zone" from PRD.md
/// "Trigger-Mechanismus". One instance per connected `NSScreen`.
///
/// Several points wide, not 1px (mouse-motor precision) and deliberately
/// NOT anchored at the top-left corner (collides with the GNOME Activities
/// hot corner on Linux -- kept consistent across platforms even though this
/// file is macOS-only). `ignoresMouseEvents` stays `false` so the tracking
/// area actually receives enter/exit; per the ticket this only needs
/// ordinary pointer enter/leave, not global cursor tracking.
class SidePanelSensorPanel: NSPanel {
  static let width: CGFloat = 6

  private let trackingView: SidePanelSensorView

  init(
    screenFrame: NSRect,
    onHoverEntered: @escaping () -> Void,
    onRawEnter: @escaping () -> Void,
    onRawExit: @escaping () -> Void
  ) {
    let rect = NSRect(
      x: screenFrame.minX,
      y: screenFrame.minY,
      width: Self.width,
      height: screenFrame.height
    )
    trackingView = SidePanelSensorView(
      onHoverEntered: onHoverEntered,
      onRawEnter: onRawEnter,
      onRawExit: onRawExit
    )
    super.init(
      contentRect: rect,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    // `.popUpMenu`, not `.floating` -- must match SidePanelContentPanel's
    // level (see its doc comment): the sensor strip is the FIRST thing a
    // stuck, higher-level drag-snap overlay would swallow input from (it's
    // the trigger the content panel never gets a chance to fix if hover
    // never reaches this strip in the first place).
    level = .popUpMenu
    // Matches FloatingOverlayPanel's collectionBehavior exactly -- an
    // empirical spike (see that file's doc comment) found this the only
    // combination that reliably stays above fullscreen spaces.
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    ignoresMouseEvents = false
    trackingView.frame = NSRect(origin: .zero, size: rect.size)
    contentView = trackingView
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  /// Re-syncs the tracking area after the sensor's frame changes (monitor
  /// geometry change).
  func updateFrame(screenFrame: NSRect) {
    let rect = NSRect(
      x: screenFrame.minX,
      y: screenFrame.minY,
      width: Self.width,
      height: screenFrame.height
    )
    setFrame(rect, display: false)
    trackingView.frame = NSRect(origin: .zero, size: rect.size)
    trackingView.rebuildTrackingArea()
  }
}

/// Plain `NSView` reporting a *dwelled* pointer enter via a tracking area:
/// [onHoverEntered] only fires after the pointer has stayed for
/// [dwellDelay], not on the raw enter event, so a pointer merely passing
/// over the edge (moving the window, reaching for another app) doesn't
/// pop the panel open. Exit before the dwell elapses cancels it.
///
/// [onRawEnter]/[onRawExit] fire immediately, no dwell -- these keep the
/// *already-open* panel alive while the pointer sits on this strip. The
/// panel's own content view starts exactly [SidePanelSensorPanel.width]
/// points to the right of this strip's right edge, so this strip and the
/// content view do not overlap; without a raw signal from here too, a
/// pointer that lingers in this strip after the dwell-open (instead of
/// continuing right onto the panel) sits in a dead zone that neither
/// tracking area considers "inside", the close grace period elapses, the
/// panel closes -- and AppKit's window-visibility-driven tracking-area
/// reconciliation then re-synthesizes a fresh `mouseEntered` right here
/// (the pointer never actually moved), restarting the dwell and reopening
/// the panel: a self-sustaining open/close flicker for as long as the
/// pointer stays on this strip instead of moving onto the panel. Routing
/// raw enter/exit here into the same close-timer cancel/schedule the
/// content view uses (see `SidePanelContentHoverTracker` in
/// `SidePanelHost.swift`) makes the strip and the content view read as one
/// continuous hover region once the panel is open, closing that gap.
class SidePanelSensorView: NSView {
  static let dwellDelay: TimeInterval = 0.06

  private let onHoverEntered: () -> Void
  private let onRawEnter: () -> Void
  private let onRawExit: () -> Void
  private var trackingArea: NSTrackingArea?
  private var dwellTimer: Timer?

  init(
    onHoverEntered: @escaping () -> Void,
    onRawEnter: @escaping () -> Void,
    onRawExit: @escaping () -> Void
  ) {
    self.onHoverEntered = onHoverEntered
    self.onRawEnter = onRawEnter
    self.onRawExit = onRawExit
    super.init(frame: .zero)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    rebuildTrackingArea()
  }

  func rebuildTrackingArea() {
    if let existing = trackingArea {
      removeTrackingArea(existing)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    onRawEnter()
    dwellTimer?.invalidate()
    // `Timer.scheduledTimer` only registers in `.default` run loop mode, but
    // `mouseEntered` fires while AppKit is in `.eventTrackingRunLoopMode` --
    // a `.default`-mode timer started here can be starved for as long as
    // pointer tracking keeps the run loop in that mode, delaying (or, for a
    // pointer that keeps re-entering, indefinitely deferring) the dwell-open.
    // `.common` covers both modes, so the dwell still elapses on schedule.
    let timer = Timer(timeInterval: Self.dwellDelay, repeats: false) { [weak self] _ in
      self?.onHoverEntered()
    }
    RunLoop.main.add(timer, forMode: .common)
    dwellTimer = timer
  }

  override func mouseExited(with event: NSEvent) {
    dwellTimer?.invalidate()
    dwellTimer = nil
    onRawExit()
  }
}
