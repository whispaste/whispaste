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
    // `.popUpMenu` keeps the panel above any
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
    // docked edge against the screen border where the desktop is still
    // visible behind it -- it reads as a grey halo/frame around the whole
    // panel rather than the intended card flush with its docked edge.
    hasShadow = false
    isMovableByWindowBackground = false
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// Decision logic of the edge trigger (#1782). Mirrors
/// `linux/runner/side_panel_edge_core.h` rule for rule (checked by
/// `test/scripts/side_panel_edge_core_test.sh`): the zone is the first
/// [zoneWidth] points along the docked edge of a screen's visible frame; a
/// fullscreen app in front counts as "not in the zone"; raw enter/exit fire
/// at once, the open signal once per visit after [dwellMs] and only while no
/// mouse button is held. Swift only, no Cocoa, so the test compiles it alone.
struct SidePanelEdgeCore {
  static let zoneWidth: Double = 6
  static let dwellMs: Int64 = 60
  static let pollMs: Int64 = 40

  struct Rect {
    var left: Double
    var top: Double
    var right: Double
    var bottom: Double
  }

  struct Events {
    var rawEnter = false
    var rawExit = false
    var open = false
  }

  static func inZone(x: Double, y: Double, workArea: Rect, width: Double, dockRight: Bool) -> Bool {
    if width <= 0 { return false }
    if y < workArea.top || y >= workArea.bottom { return false }
    if x < workArea.left || x >= workArea.right { return false }
    return dockRight ? x >= workArea.right - width : x < workArea.left + width
  }

  static func coversMonitor(window: Rect, monitor: Rect) -> Bool {
    if monitor.right <= monitor.left || monitor.bottom <= monitor.top { return false }
    return window.left <= monitor.left && window.top <= monitor.top
      && window.right >= monitor.right && window.bottom >= monitor.bottom
  }

  struct Tracker {
    let dwellMs: Int64
    private(set) var inside = false
    private var opened = false
    private var enteredMs: Int64 = 0

    init(dwellMs: Int64 = SidePanelEdgeCore.dwellMs) {
      self.dwellMs = dwellMs
    }

    mutating func update(inZone: Bool, buttonsDown: Bool, nowMs: Int64) -> Events {
      var e = Events()
      if !inZone {
        if inside {
          inside = false
          e.rawExit = true
        }
        return e
      }
      if !inside {
        inside = true
        opened = false
        enteredMs = nowMs
        e.rawEnter = true
      }
      if buttonsDown {
        enteredMs = nowMs
        return e
      }
      if !opened && nowMs - enteredMs >= dwellMs {
        opened = true
        e.open = true
      }
      return e
    }

    mutating func reset() {
      inside = false
      opened = false
      enteredMs = 0
    }
  }
}

/// Edge trigger of the side panel without a window (#1782).
///
/// Used to be a transparent, always-on-top `NSPanel` strip per screen at
/// `.popUpMenu` level that joined every Space, fullscreen ones included. It
/// took every mouse event at the screen edge, which broke games that scroll
/// their camera there, and it existed from app start, even with the panel
/// switched off. This samples `NSEvent.mouseLocation` instead (no permission
/// needed, nothing at the edge takes input) and runs only while
/// `SidePanelHost` has armed it, i.e. while the panel is enabled. The rules
/// live in [SidePanelEdgeCore].
final class SidePanelEdgeWatcher {
  /// Fired once per visit after the dwell, with the visible frame of the
  /// screen whose edge the pointer rests on.
  var onHoverEntered: ((NSRect) -> Void)?
  /// Fired at once on entering/leaving the zone; keeps an open panel alive
  /// while the pointer sits on the edge instead of on the panel.
  var onRawEnter: (() -> Void)?
  var onRawExit: (() -> Void)?

  var dockRight = false {
    didSet { if dockRight != oldValue { tracker.reset() } }
  }

  private var tracker = SidePanelEdgeCore.Tracker()
  private var timer: Timer?

  /// The fullscreen check reads the window list, so it is cached briefly and
  /// only made while the pointer is at the edge.
  private static let fullscreenCacheMs: Int64 = 500
  private var fullscreenCheckedMs: Int64 = -1_000_000
  private var fullscreenCached = false

  var isRunning: Bool { timer != nil }

  func start() {
    guard timer == nil else { return }
    tracker.reset()
    let t = Timer(
      timeInterval: Double(SidePanelEdgeCore.pollMs) / 1000, repeats: true
    ) { [weak self] _ in
      self?.poll()
    }
    t.tolerance = 0.01
    // `.common`, not `.default`: during pointer tracking AppKit runs the
    // main loop in `.eventTrackingRunLoopMode`, which would starve the poll.
    RunLoop.main.add(t, forMode: .common)
    timer = t
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    tracker.reset()
  }

  private static func nowMs() -> Int64 {
    Int64(ProcessInfo.processInfo.systemUptime * 1000)
  }

  private func poll() {
    let mouse = NSEvent.mouseLocation
    let now = Self.nowMs()
    var inZone = false
    var visible = NSRect.zero
    if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
      visible = screen.visibleFrame
      // Cocoa's y grows upwards; the core only compares ranges, so
      // bottom/top swap is all it takes.
      let work = SidePanelEdgeCore.Rect(
        left: Double(visible.minX), top: Double(visible.minY),
        right: Double(visible.maxX), bottom: Double(visible.maxY))
      inZone = SidePanelEdgeCore.inZone(
        x: Double(mouse.x), y: Double(mouse.y), workArea: work,
        width: SidePanelEdgeCore.zoneWidth, dockRight: dockRight)
      if inZone && fullscreenAppInFront(on: screen, nowMs: now) {
        inZone = false
      }
    }
    let events = tracker.update(
      inZone: inZone, buttonsDown: NSEvent.pressedMouseButtons != 0, nowMs: now)
    if events.rawEnter { onRawEnter?() }
    if events.open { onHoverEntered?(visible) }
    if events.rawExit { onRawExit?() }
  }

  private func fullscreenAppInFront(on screen: NSScreen, nowMs: Int64) -> Bool {
    if nowMs - fullscreenCheckedMs < Self.fullscreenCacheMs {
      return fullscreenCached
    }
    fullscreenCheckedMs = nowMs
    fullscreenCached = Self.frontAppCovers(screen)
    return fullscreenCached
  }

  /// Whether the frontmost app (not WhisPaste) has a normal-level window
  /// that fills the whole screen: a fullscreen game, video or slideshow, in
  /// its own Space or borderless. Window bounds and owner PIDs are readable
  /// without the screen-recording permission (only titles need it).
  private static func frontAppCovers(_ screen: NSScreen) -> Bool {
    guard let front = NSWorkspace.shared.frontmostApplication,
      front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
      let primary = NSScreen.screens.first,
      let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]]
    else { return false }
    // Window-list bounds are top-left based on the primary screen.
    let f = screen.frame
    let monitor = SidePanelEdgeCore.Rect(
      left: Double(f.minX), top: Double(primary.frame.maxY - f.maxY),
      right: Double(f.maxX), bottom: Double(primary.frame.maxY - f.minY))
    for info in list {
      guard (info[kCGWindowOwnerPID as String] as? pid_t) == front.processIdentifier,
        (info[kCGWindowLayer as String] as? Int) == 0,
        let dict = info[kCGWindowBounds as String] as? NSDictionary,
        let b = CGRect(dictionaryRepresentation: dict as CFDictionary)
      else { continue }
      let window = SidePanelEdgeCore.Rect(
        left: Double(b.minX), top: Double(b.minY),
        right: Double(b.maxX), bottom: Double(b.maxY))
      if SidePanelEdgeCore.coversMonitor(window: window, monitor: monitor) { return true }
    }
    return false
  }
}
