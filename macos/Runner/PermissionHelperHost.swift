import ApplicationServices
import Cocoa
import FlutterMacOS

/// MethodChannel host for the onboarding permission helper
/// (`whispaste/permission_helper`, `internal-notes
/// intro-av/spec.md`, "macOS accessibility permission helper").
///
/// `show(kind, text)` opens System Settings > Privacy > Accessibility and
/// docks a small non-activating panel to the bottom edge of the System
/// Settings window: the localised [text] from Dart and, under an arrow, a lit
/// dashed tile with the app icon that the user drags into the list. Every 0.5 s the host
/// checks `AXIsProcessTrusted()` and follows the window. On the grant it
/// closes the panel and calls `granted` on the channel; after 5 minutes, or
/// when the user quits System Settings or presses its close button, it
/// closes and calls `closed` with the
/// reason. `hide()` closes it without an event.
///
/// Answers of `show`: "shown", "granted" (already trusted, nothing shown),
/// "unsupported" (unknown kind, or the Mac App Store build: the sandbox
/// cannot use the Accessibility API, see `DesktopPasteHost`).
///
/// The panel never animates, so "reduce motion" needs no special case.
/// Windows and Linux need no such grant; their Dart side returns
/// "unsupported" without calling a native host.
final class PermissionHelperHost: NSObject {
  private let channel: FlutterMethodChannel
  private var panel: NSPanel?
  private var timer: Timer?
  private var kind: String?
  private var shownAt = Date()
  private var settingsSeen = false

  private static let pollInterval: TimeInterval = 0.5
  private static let timeout: TimeInterval = 300
  private static let settingsBundleId = "com.apple.systempreferences"
  private static let panelSize = NSSize(width: 440, height: 124)

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
      let closeLabel = args?["closeLabel"] as? String ?? "Close"
      result(show(kind: kind, text: text, closeLabel: closeLabel))

    case "hide":
      close(event: nil)
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func show(kind: String, text: String, closeLabel: String) -> String {
#if MAS_BUILD
    return "unsupported"
#else
    guard kind == "accessibility" else { return "unsupported" }
    if AXIsProcessTrusted() { return "granted" }
    close(event: nil)
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
    self.kind = kind
    shownAt = Date()
    settingsSeen = false
    let panel = makePanel(text: text, closeLabel: closeLabel)
    self.panel = panel
    position(panel)
    panel.orderFrontRegardless()
    timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      self?.tick()
    }
    return "shown"
#endif
  }

  private func tick() {
    guard let panel = panel, let kind = kind else { return }
    if AXIsProcessTrusted() {
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
  }

  @objc private func closeTapped() {
    guard let kind = kind else { return }
    close(event: ("closed", ["kind": kind, "reason": "cancelled"]))
  }

  private func close(event: (String, [String: String])?) {
    timer?.invalidate()
    timer = nil
    panel?.orderOut(nil)
    panel = nil
    kind = nil
    if let (method, args) = event {
      channel.invokeMethod(method, arguments: args)
    }
  }

  // MARK: Panel

  private func makePanel(text: String, closeLabel: String) -> NSPanel {
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

    let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Self.panelSize))
    background.material = .hudWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 12
    background.layer?.masksToBounds = true

    let label = NSTextField(wrappingLabelWithString: text)
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.maximumNumberOfLines = 3

    // The tile reads as something to grab: a lit, dashed well with an arrow
    // above it, and the tile nudges upward now and then (not under Reduce
    // Motion). Users missed the plain icon as a drag source.
    let tile = DragTileView()
    tile.setAccessibilityLabel(text)

    let arrow = NSTextField(labelWithString: "\u{2191}")
    arrow.font = .systemFont(ofSize: 22, weight: .bold)
    arrow.textColor = .controlAccentColor
    arrow.alignment = .center
    arrow.setAccessibilityElement(false)

    let grab = NSStackView(views: [arrow, tile])
    grab.orientation = .vertical
    grab.alignment = .centerX
    grab.spacing = 2

    let row = NSStackView(views: [label, grab])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 16
    // The texts say "on the right"; keep the tile there in every language.
    row.userInterfaceLayoutDirection = .leftToRight
    row.edgeInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 16)
    row.translatesAutoresizingMaskIntoConstraints = false
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

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
      tile.widthAnchor.constraint(equalToConstant: 76),
      tile.heightAnchor.constraint(equalToConstant: 76),
    ])
    tile.startNudging()
    panel.contentView = background
    return panel
  }

  /// Docks the panel under the System Settings window (inside its bottom edge
  /// when there is no room below), or at the bottom of the main screen while
  /// the window is not found yet. Window bounds need no screen-recording
  /// permission; window titles are never read.
  private func position(_ panel: NSPanel) {
    let size = Self.panelSize
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    var origin = NSPoint(
      x: screen.visibleFrame.midX - size.width / 2,
      y: screen.visibleFrame.minY + 24
    )
    if let frame = settingsWindowFrame() {
      origin.x = frame.midX - size.width / 2
      origin.y = frame.minY - size.height - 8
      if origin.y < screen.visibleFrame.minY {
        origin.y = frame.minY + 16
      }
    }
    panel.setFrameOrigin(origin)
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

/// The draggable app tile: drags the running app's bundle URL, which is what
/// the Accessibility list accepts.
private final class DragTileView: NSView, NSDraggingSource {
  private let icon = NSApp.applicationIconImage ?? NSImage()
  private var nudgeTimer: Timer?
  private var lift: CGFloat = 0

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityRole(.button)
    translatesAutoresizingMaskIntoConstraints = false
  }

  required init?(coder: NSCoder) { nil }

  deinit { nudgeTimer?.invalidate() }

  /// Lifts the icon a few points every 1.6 s, as if it wanted to go up.
  func startNudging() {
    guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
    nudgeTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
      guard let self else { return }
      self.lift = 6
      self.needsDisplay = true
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
        self?.lift = 0
        self?.needsDisplay = true
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    let well = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
    NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
    well.fill()
    well.lineWidth = 1.5
    well.setLineDash([5, 3], count: 2, phase: 0)
    NSColor.controlAccentColor.withAlphaComponent(0.8).setStroke()
    well.stroke()
    icon.draw(in: bounds.insetBy(dx: 10, dy: 10).offsetBy(dx: 0, dy: lift))
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .openHand)
  }

  override func mouseDown(with event: NSEvent) {
    let item = NSDraggingItem(pasteboardWriter: Bundle.main.bundleURL as NSURL)
    item.setDraggingFrame(bounds, contents: icon)
    beginDraggingSession(with: [item], event: event, source: self)
  }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    context == .outsideApplication ? .copy : []
  }
}
