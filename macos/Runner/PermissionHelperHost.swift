import ApplicationServices
import AVFoundation
import Cocoa
import FlutterMacOS

/// MethodChannel host for the onboarding permission helper
/// (`whispaste/permission_helper`).
///
/// `show(kind, text, note)` opens System Settings > Privacy > Accessibility
/// (kind `accessibility`) or > Input Monitoring (kind `inputMonitoring`, the
/// single-key trigger, #1198), or leaves that to the system dialog when it is up, and places a small non-activating panel next to the System Settings window
/// (`PermissionPanelPlacement`, off its list and +/− buttons): the localised
/// [text] and [note] from Dart and, under an arrow that points to the list, the
/// same picture on both builds (`PermissionGuideView`): the list row whose
/// switch turns on; on the Developer-ID build it can also be dragged into the
/// list. The panel floats only while System Settings
/// is the active app; with any other app in front it is hidden. The user can
/// move the panel by its background; from then on it only keeps its offset to
/// the window. Every 0.5 s the host checks the kind's grant
/// ([SyntheticEventAccess.granted] or `CGPreflightListenEventAccess()`) and
/// follows the window. On the grant it closes the panel and calls `granted` on
/// the channel; after 5 minutes, or
/// when the user quits System Settings or presses its close button, it
/// closes and calls `closed` with the
/// reason. `hide()` closes it without an event.
///
/// Answers of `show`: "shown", "granted" (already trusted, nothing shown),
/// "unsupported" (unknown kind).
///
/// Under "Reduce motion" the picture is a still with the switch on.
/// Windows and Linux need no such grant; their Dart side returns
/// "unsupported" without calling a native host.
final class PermissionHelperHost: NSObject {
  private let channel: FlutterMethodChannel
  private var panel: NSPanel?
  private var timer: Timer?
  private var kind: String?
  private var shownAt = Date()
  private var settingsSeen = false
  /// The settings window frame the panel was last placed against.
  private var placedAgainst: NSRect?
  private var placed = false
  /// Set once the user dragged the panel; no automatic placement after that.
  private var userMoved = false
  /// The panel's offset to the settings window after the user's move, kept
  /// when the window moves.
  private var userOffset: NSPoint?
  /// True while the host itself moves the panel, so its own moves are not
  /// taken for the user's.
  private var placing = false
  private var moveObserver: NSObjectProtocol?
  private var activationObserver: NSObjectProtocol?
  private var arrow: NSTextField?
  private var guide: PermissionGuideView?

  private static let pollInterval: TimeInterval = 0.5
  private static let timeout: TimeInterval = 300
  private static let settingsBundleId = "com.apple.systempreferences"
  private static let systemDialogBundleId = "com.apple.accessibility.universalAccessAuthWarn"
  private static let systemDialogGrace: TimeInterval = 0.7
#if MAS_BUILD
  /// Nothing is dragged here, so the panel may sit closer to the row: it
  /// reaches over the empty strip under the list and the +/− buttons.
  private static let bottomLift: CGFloat = 64
#else
  private static let bottomLift: CGFloat = 0
#endif
  private static let panelSize = NSSize(width: 440, height: 140)
  /// Narrower and taller (the texts wrap), for the room beside the window on
  /// a small screen.
  private static let compactPanelSize = NSSize(width: 380, height: 168)

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "whispaste/permission_helper",
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "show":
      let args = call.arguments as? [String: Any]
      guard let kind = args?["kind"] as? String,
            let text = args?["text"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing 'kind' or 'text'", details: nil))
        return
      }
      let note = args?["note"] as? String ?? ""
      let closeLabel = args?["closeLabel"] as? String ?? "Close"
      result(show(kind: kind, text: text, note: note, closeLabel: closeLabel))

    case "hide":
      close(event: nil)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func show(kind: String, text: String, note: String, closeLabel: String) -> String {
    guard Self.paneAnchors[kind] != nil else { return "unsupported" }
    if Self.isGranted(kind) { return "granted" }
    close(event: nil)
    self.kind = kind
    shownAt = Date()
    settingsSeen = false
    let panel = makePanel(text: text, note: note, closeLabel: closeLabel)
    self.panel = panel
    placedAgainst = nil
    placed = false
    userMoved = false
    userOffset = nil
    position(panel)
    moveObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didMoveNotification, object: panel, queue: .main
    ) { [weak self] _ in
      self?.panelMoved()
    }
    activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in
      self?.syncVisibility()
    }
    syncVisibility()
    openSettingsUnlessSystemDialogIsUp()
    timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      self?.tick()
    }
    return "shown"
  }

  /// The System Settings anchor of each supported kind.
  private static let paneAnchors = [
    "accessibility": "Privacy_Accessibility",
    "inputMonitoring": "Privacy_ListenEvent",
  ]

  /// Whether the permission behind [kind] is granted, read live.
  private static func isGranted(_ kind: String) -> Bool {
    switch kind {
    case "inputMonitoring": return CGPreflightListenEventAccess()
    default: return SyntheticEventAccess.granted
    }
  }

  private func tick() {
    guard let panel = panel, let kind = kind else { return }
    if Self.isGranted(kind) {
      close(event: ("granted", ["kind": kind]))
      return
    }
    if Date().timeIntervalSince(shownAt) > Self.timeout {
      close(event: ("closed", ["kind": kind, "reason": "timeout"]))
      return
    }
    let settingsRunning = !NSRunningApplication
      .runningApplications(withBundleIdentifier: Self.settingsBundleId).isEmpty
    if settingsRunning {
      settingsSeen = true
    } else if settingsSeen {
      close(event: ("closed", ["kind": kind, "reason": "cancelled"]))
      return
    }
    position(panel)
    syncVisibility()
  }

  /// Shows the panel only over System Settings: with another app in front it
  /// would float over that app's windows (maintainer report, 2026-11-02). The
  /// panel does not activate, so dragging the picture keeps System Settings in front.
  /// The first permission request raises a system dialog whose own button
  /// opens System Settings; opening them here as well would leave that dialog
  /// behind the window. So with the dialog up the user goes through it and the
  /// panel appears once System Settings comes to the front. Without it, as on
  /// every later request, nothing else would open them. The dialog's process
  /// starts just after the request, hence the short wait.
  private func openSettingsUnlessSystemDialogIsUp() {
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.systemDialogGrace) { [weak self] in
      guard let self, self.panel != nil else { return }
      // The dialog process stays alive in the background after it was closed
      // (#901), so only a dialog with a window on screen counts; otherwise
      // System Settings opens.
      let windows =
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
      let dialog = NSRunningApplication.runningApplications(
        withBundleIdentifier: Self.systemDialogBundleId
      ).first { SystemDialogPresence.hasWindowOnScreen(pid: $0.processIdentifier, windows: windows) }
      if let dialog {
        dialog.activate(options: [])
      } else if let anchor = self.kind.flatMap({ Self.paneAnchors[$0] }),
                let url = URL(
                  string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
                ) {
        NSWorkspace.shared.open(url)
      }
    }
  }

  private func syncVisibility() {
    guard let panel else { return }
    let settingsInFront =
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.settingsBundleId
    if settingsInFront, !panel.isVisible {
      panel.orderFrontRegardless()
    } else if !settingsInFront, panel.isVisible {
      panel.orderOut(nil)
    }
  }

  @objc private func closeTapped() {
    guard let kind = kind else { return }
    close(event: ("closed", ["kind": kind, "reason": "cancelled"]))
  }

  private func close(event: (String, [String: String])?) {
    timer?.invalidate()
    timer = nil
    if let moveObserver {
      NotificationCenter.default.removeObserver(moveObserver)
    }
    moveObserver = nil
    if let activationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
    }
    activationObserver = nil
    panel?.orderOut(nil)
    panel = nil
    arrow = nil
    guide = nil
    kind = nil
    if let (method, args) = event {
      channel.invokeMethod(method, arguments: args)
    }
  }

  // MARK: Panel

  private func makePanel(text: String, note: String, closeLabel: String) -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(origin: .zero, size: Self.panelSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    // Users move it off whatever it still covers; on the Developer-ID build
    // the picture's own drag does not move the panel
    // (PermissionGuideView.mouseDownCanMoveWindow).
    panel.isMovableByWindowBackground = true

    let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
    background.material = .hudWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 12
    background.layer?.masksToBounds = true
    background.setAccessibilityIdentifier("permission-helper-panel")

    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.maximumNumberOfLines = 4

    // A reinstall or a new signature can leave an old entry in the list that
    // blocks the new one; it has to go with "−" first.
    let noteLabel = NSTextField(wrappingLabelWithString: note)
    noteLabel.font = .systemFont(ofSize: 12)
    noteLabel.textColor = .secondaryLabelColor
    noteLabel.maximumNumberOfLines = 3
    noteLabel.isHidden = note.isEmpty

    let texts = NSStackView(views: [label, noteLabel])
    texts.orientation = .vertical
    texts.alignment = .leading
    texts.spacing = 4

    // The guide sits under an arrow that points to the list. `position` sets
    // the direction for the panel's spot.
    let guide = PermissionGuideView()
    guide.setAccessibilityLabel(text)

    let arrow = NSTextField(labelWithString: "\u{2191}")
    arrow.font = .systemFont(ofSize: 22, weight: .bold)
    arrow.textColor = .controlAccentColor
    arrow.alignment = .center
    arrow.setAccessibilityElement(false)

    let grab = NSStackView(views: [arrow, guide])
    grab.orientation = .vertical
    grab.alignment = .centerX
    grab.spacing = 2

    let row = NSStackView(views: [texts, grab])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 16
    // The texts say "on the right"; keep the guide there in every language.
    row.userInterfaceLayoutDirection = .leftToRight
    row.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 16)
    row.translatesAutoresizingMaskIntoConstraints = false
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    noteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    // Always a way out: dragging may do nothing (a stale entry, a list that
    // did not open), and a floating panel without a close control traps the
    // user (maintainer report, 2026-10-30).
    let close = NSButton(
      image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: closeLabel)
        ?? NSImage(),
      target: self,
      action: #selector(closeTapped)
    )
    close.isBordered = false
    close.contentTintColor = .tertiaryLabelColor
    close.toolTip = closeLabel
    close.setAccessibilityLabel(closeLabel)
    close.setAccessibilityIdentifier("permission-helper-close")
    close.translatesAutoresizingMaskIntoConstraints = false

    background.addSubview(row)
    background.addSubview(close)
    NSLayoutConstraint.activate([
      close.topAnchor.constraint(equalTo: background.topAnchor, constant: 6),
      close.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -6),
      close.widthAnchor.constraint(equalToConstant: 18),
      close.heightAnchor.constraint(equalToConstant: 18),
      row.leadingAnchor.constraint(equalTo: background.leadingAnchor),
      row.trailingAnchor.constraint(equalTo: background.trailingAnchor),
      row.topAnchor.constraint(equalTo: background.topAnchor),
      row.bottomAnchor.constraint(equalTo: background.bottomAnchor),
      guide.widthAnchor.constraint(equalToConstant: PermissionGuideView.size.width),
      guide.heightAnchor.constraint(equalToConstant: PermissionGuideView.size.height),
    ])
    panel.contentView = background
    guide.load()
    self.arrow = arrow
    self.guide = guide
    return panel
  }

  /// Places the panel next to the System Settings window
  /// (`PermissionPanelPlacement`) when the window appeared or moved, at the
  /// spot's size and with the arrow toward the list. After the user moved the
  /// panel, it only follows the window with the same offset.
  /// Window bounds need no screen-recording permission; window titles are
  /// never read.
  private func position(_ panel: NSPanel) {
    let window = settingsWindowFrame()
    if userMoved {
      guard let window, window != placedAgainst else { return }
      if let offset = userOffset {
        move(panel, to: NSPoint(x: window.minX + offset.x, y: window.minY + offset.y))
      } else {
        // Moved before the window was found: keep the spot, follow from now on.
        userOffset = NSPoint(x: panel.frame.minX - window.minX, y: panel.frame.minY - window.minY)
      }
      placedAgainst = window
      return
    }
    if window == nil ? placed : window == placedAgainst { return }
    let screens = NSScreen.screens.map(\.visibleFrame)
    let fallback = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
    // System Settings mirrors its sidebar in right-to-left languages.
    let sidebarOnLeft = NSLocale.characterDirection(
      forLanguage: Locale.preferredLanguages.first ?? "en"
    ) != .rightToLeft
    let spot = PermissionPanelPlacement.spot(
      regular: Self.panelSize,
      compact: Self.compactPanelSize,
      window: window,
      screen: PermissionPanelPlacement.screen(for: window, among: screens) ?? fallback,
      sidebarOnLeft: sidebarOnLeft,
      bottomLift: Self.bottomLift
    )
    placedAgainst = window
    placed = true
    arrow?.stringValue = PermissionPanelPlacement.arrow(for: spot.side)
    placing = true
    panel.setFrame(spot.frame, display: true)
    placing = false
  }

  private func move(_ panel: NSPanel, to origin: NSPoint) {
    placing = true
    panel.setFrameOrigin(origin)
    placing = false
  }

  private func panelMoved() {
    guard !placing, let panel else { return }
    userMoved = true
    if let window = placedAgainst {
      userOffset = NSPoint(x: panel.frame.minX - window.minX, y: panel.frame.minY - window.minY)
    }
  }

  /// The largest normal-layer window of System Settings in Cocoa coordinates.
  private func settingsWindowFrame() -> NSRect? {
    guard let pid = NSRunningApplication
      .runningApplications(withBundleIdentifier: Self.settingsBundleId).first?
      .processIdentifier,
      let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]],
      let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
    var best: CGRect?
    for info in infos {
      guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
            (info[kCGWindowLayer as String] as? Int) == 0,
            let dict = info[kCGWindowBounds as String] as? NSDictionary,
            let rect = CGRect(dictionaryRepresentation: dict) else { continue }
      if best == nil || rect.width * rect.height > best!.width * best!.height {
        best = rect
      }
    }
    guard let r = best else { return nil }
    // CoreGraphics counts from the top of the primary screen, Cocoa from the bottom.
    return NSRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
  }
}

/// The panel's picture (#753), the same in the Developer-ID and the Mac App
/// Store build: one row of the System Settings list with the app icon, a
/// pointer clicks its switch and the switch turns on. No text in the picture,
/// the words stay next to it. A looping clip rendered from
/// `website/motion/permission-guide` (assets/permission_guide/, light and dark
/// by the panel's appearance); under "Reduce motion" its still frame, switch
/// on. On the Developer-ID build the same picture can also be dragged into the
/// list (it drags the app's bundle URL), the way out when the row is missing;
/// on the store build `CGRequestPostEventAccess()` already created the row and
/// a dropped app would only add an entry the sandbox cannot use.
private final class PermissionGuideView: NSView {
  static let size = NSSize(width: 200, height: 64)
  private static let assetDir = "assets/permission_guide"

  private let playerLayer = AVPlayerLayer()
  private let stillLayer = CALayer()
  private var player: AVQueuePlayer?
  private var looper: AVPlayerLooper?
  private var theme: String?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    translatesAutoresizingMaskIntoConstraints = false
    setAccessibilityElement(true)
    setAccessibilityIdentifier("permission-helper-guide")
#if MAS_BUILD
    setAccessibilityRole(.image)
#else
    setAccessibilityRole(.button)
#endif
    wantsLayer = true
    layer?.cornerRadius = 10
    layer?.masksToBounds = true
    playerLayer.videoGravity = .resizeAspect
    stillLayer.contentsGravity = .resizeAspect
    layer?.addSublayer(stillLayer)
    layer?.addSublayer(playerLayer)
  }

  required init?(coder: NSCoder) { nil }

  deinit { player?.pause() }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    playerLayer.frame = bounds
    stillLayer.frame = bounds
    CATransaction.commit()
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    load()
  }

  /// Loads the light or dark picture; the clip only without "Reduce motion".
  func load() {
    let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let theme = dark ? "dunkel" : "hell"
    guard theme != self.theme else { return }
    self.theme = theme
    stillLayer.contents = Self.asset("guide-\(theme).png").flatMap { NSImage(contentsOf: $0) }
    player?.pause()
    looper = nil
    player = nil
    playerLayer.player = nil
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
          let clip = Self.asset("guide-\(theme).mp4") else { return }
    let queue = AVQueuePlayer()
    queue.isMuted = true
    queue.preventsDisplaySleepDuringVideoPlayback = false
    looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: clip))
    player = queue
    playerLayer.player = queue
    queue.play()
  }

  /// A Flutter asset inside the bundle (App.framework/Resources/flutter_assets),
  /// where both builds carry it.
  private static func asset(_ name: String) -> URL? {
    guard let url = Bundle.main.privateFrameworksURL?
      .appendingPathComponent("App.framework/Resources/flutter_assets")
      .appendingPathComponent(assetDir)
      .appendingPathComponent(name),
      FileManager.default.fileExists(atPath: url.path) else { return nil }
    return url
  }

#if !MAS_BUILD
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  // Dragging the picture drags the app, not the movable panel.
  override var mouseDownCanMoveWindow: Bool { false }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func mouseDown(with event: NSEvent) {
    let icon = NSApp.applicationIconImage ?? NSImage()
    let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
    let side = bounds.height
    item.setDraggingFrame(NSRect(x: 0, y: 0, width: side, height: side), contents: icon)
    beginDraggingSession(with: [item], event: event, source: self)
  }
#endif
}

#if !MAS_BUILD
extension PermissionGuideView: NSDraggingSource {
  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .outsideApplication ? .copy : []
  }
}
#endif

/// Whether a process shows a window on screen, read from a
/// `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` list (#901).
enum SystemDialogPresence {
  static func hasWindowOnScreen(pid: pid_t, windows: [[String: Any]]) -> Bool {
    windows.contains { info in
      guard (info[kCGWindowOwnerPID as String] as? Int).map({ pid_t($0) }) == pid else {
        return false
      }
      let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
      guard alpha > 0 else { return false }
      guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
        let width = bounds["Width"] as? Double, let height = bounds["Height"] as? Double
      else { return false }
      return width > 1 && height > 1
    }
  }
}

/// Where the permission panel goes, as a pure function of the System Settings
/// window and the visible frame of its screen (Cocoa coordinates). The list and
/// its +/− buttons stay free wherever there is any way to do so. Order: below
/// the window; beside it (the side with more room), first at full width, then
/// at the narrower [compact] width; above it; beside it over the window's
/// sidebar, which the drag does not need; and as a last resort over the top of
/// the window, which covers the title bar and the pane header and, on a small
/// screen, can reach the first row (a 1280-point display has room beside a
/// left-aligned window at the compact width). Without a window: bottom centre
/// of the screen. [Spot.side] tells the arrow which way the list lies.
/// `bottomLift` moves the spot below the window up by that much.
enum PermissionPanelPlacement {
  static let gap: CGFloat = 8
  static let screenInset: CGFloat = 24
  /// How far the panel may reach over the System Settings sidebar (about
  /// 215 to 260 points wide since macOS 13) without touching the list.
  static let sidebarOverlap: CGFloat = 180

  /// Where the panel sits relative to the window.
  enum Side: Equatable {
    case below, right, left, above, overTop, noWindow
  }

  struct Spot: Equatable {
    let frame: NSRect
    let side: Side
  }

  /// The arrow over the picture points from the panel to the list.
  static func arrow(for side: Side) -> String {
    switch side {
    case .below, .noWindow: return "\u{2191}"
    case .above, .overTop: return "\u{2193}"
    case .right: return "\u{2190}"
    case .left: return "\u{2192}"
    }
  }

  static func spot(
    regular: NSSize,
    compact: NSSize,
    window: NSRect?,
    screen: NSRect,
    sidebarOnLeft: Bool = true,
    bottomLift: CGFloat = 0
  ) -> Spot {
    guard let w = window else {
      let origin = NSPoint(x: screen.midX - regular.width / 2, y: screen.minY + screenInset)
      return Spot(frame: NSRect(origin: origin, size: regular), side: .noWindow)
    }
    func centredX(_ size: NSSize) -> CGFloat {
      clamp(w.midX - size.width / 2, screen.minX, screen.maxX - size.width)
    }
    // Level with the window's bottom, where the +/− buttons are.
    func besideY(_ size: NSSize) -> CGFloat {
      clamp(w.minY, screen.minY, screen.maxY - size.height)
    }
    let below = w.minY - gap + bottomLift - regular.height
    if below >= screen.minY {
      return Spot(frame: NSRect(origin: NSPoint(x: centredX(regular), y: below), size: regular), side: .below)
    }
    let roomRight = screen.maxX - w.maxX - gap
    let roomLeft = w.minX - screen.minX - gap
    for size in [regular, compact] where max(roomRight, roomLeft) >= size.width {
      let toRight = roomRight >= roomLeft
      let x = toRight ? w.maxX + gap : w.minX - gap - size.width
      return Spot(
        frame: NSRect(origin: NSPoint(x: x, y: besideY(size)), size: size),
        side: toRight ? .right : .left
      )
    }
    let above = w.maxY + gap
    if above + regular.height <= screen.maxY {
      return Spot(frame: NSRect(origin: NSPoint(x: centredX(regular), y: above), size: regular), side: .above)
    }
    if sidebarOnLeft, w.minX + sidebarOverlap - screen.minX >= compact.width {
      let x = w.minX + sidebarOverlap - compact.width
      return Spot(frame: NSRect(origin: NSPoint(x: x, y: besideY(compact)), size: compact), side: .left)
    }
    if !sidebarOnLeft, screen.maxX - (w.maxX - sidebarOverlap) >= compact.width {
      let x = w.maxX - sidebarOverlap
      return Spot(frame: NSRect(origin: NSPoint(x: x, y: besideY(compact)), size: compact), side: .right)
    }
    let y = clamp(min(w.maxY, screen.maxY) - gap - compact.height, screen.minY, screen.maxY - compact.height)
    return Spot(frame: NSRect(origin: NSPoint(x: centredX(compact), y: y), size: compact), side: .overTop)
  }

  /// The visible frame of the screen that holds most of [window].
  static func screen(for window: NSRect?, among screens: [NSRect]) -> NSRect? {
    guard let window else { return nil }
    var best: NSRect?
    var bestArea: CGFloat = 0
    for screen in screens {
      let part = screen.intersection(window)
      let area = part.isNull ? 0 : part.width * part.height
      if area > bestArea {
        best = screen
        bestArea = area
      }
    }
    return best
  }

  private static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(v, lo), max(lo, hi))
  }
}
