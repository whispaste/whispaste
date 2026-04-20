import Cocoa
import FlutterMacOS

/// NSPanel subclass for the floating overlay — non-activating, always-on-top.
class FloatingOverlayPanel: NSPanel {
  init(width: CGFloat = 320, height: CGFloat = 180) {
    let frame = NSRect(x: 100, y: 100, width: width, height: height)
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

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Recording state the overlay displays.
enum OverlayRecordingState: String {
  case idle, listening, recording, transcribing, processing, done, error
}

/// Main view for the floating overlay.
///
/// Shows a compact status bar with recording state, an optional waveform
/// indicator, transcription text, and action buttons.
class FloatingOverlayView: NSView {
  // MARK: - Public State

  var recordingState: OverlayRecordingState = .idle { didSet { needsDisplay = true } }
  var labelText: String = "" { didSet { needsDisplay = true } }
  var transcriptText: String = "" { didSet { needsDisplay = true } }
  var elapsedText: String = "" { didSet { needsDisplay = true } }
  var hintText: String = "" { didSet { needsDisplay = true } }
  var errorMessage: String? { didSet { needsDisplay = true } }
  var showRetry: Bool = false { didSet { needsDisplay = true } }
  var audioLevel: Float = 0 { didSet { needsDisplay = true } }
  var progressValue: Double = 0 { didSet { needsDisplay = true } }
  var masterOpacity: CGFloat = 1.0 { didSet { needsDisplay = true } }
  var isDark: Bool = true { didSet { needsDisplay = true } }
  var contextMenuItems: [[String: Any]] = []

  // MARK: - Callbacks

  var onDragEnded: ((_ x: CGFloat, _ y: CGFloat) -> Void)?
  var onCloseClicked: (() -> Void)?
  var onBodyClicked: (() -> Void)?
  var onRetryClicked: (() -> Void)?
  var onContextMenu: ((_ itemId: String) -> Void)?

  // MARK: - Internal

  private var isDragging = false
  private var dragStart: NSPoint = .zero
  private let cornerRadius: CGFloat = 12

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.clear(bounds)

    let bgColor = isDark
      ? NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.92 * masterOpacity)
      : NSColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 0.92 * masterOpacity)

    let path = CGPath(
      roundedRect: bounds,
      cornerWidth: cornerRadius,
      cornerHeight: cornerRadius,
      transform: nil
    )
    ctx.addPath(path)
    ctx.setFillColor(bgColor.cgColor)
    ctx.fillPath()

    // State bar at top.
    drawStateBar(in: ctx)

    // Label and elapsed text below state bar.
    drawLabel()

    // Audio level indicator.
    if recordingState == .recording || recordingState == .listening {
      drawAudioLevel(in: ctx)
    }

    // Progress bar for transcribing/processing.
    if recordingState == .transcribing || recordingState == .processing {
      drawProgressBar(in: ctx)
    }

    // Transcript or error text.
    if let error = errorMessage, !error.isEmpty {
      drawErrorMessage(error)
    } else {
      drawTranscript()
    }

    // Retry button for error state.
    if showRetry {
      drawRetryButton(in: ctx)
    }

    // Close button (top-right).
    drawCloseButton(in: ctx)

    // Border.
    let borderColor = isDark
      ? NSColor.white.withAlphaComponent(0.08 * masterOpacity)
      : NSColor.black.withAlphaComponent(0.06 * masterOpacity)
    ctx.addPath(path)
    ctx.setStrokeColor(borderColor.cgColor)
    ctx.setLineWidth(1)
    ctx.strokePath()
  }

  private func drawStateBar(in ctx: CGContext) {
    let barH: CGFloat = 4
    let barRect = NSRect(x: 0, y: bounds.height - barH, width: bounds.width, height: barH)

    let color: NSColor = switch recordingState {
    case .idle, .listening:
      isDark
        ? NSColor(red: 0.4, green: 0.4, blue: 0.45, alpha: masterOpacity)
        : NSColor(red: 0.7, green: 0.7, blue: 0.75, alpha: masterOpacity)
    case .recording:
      NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: masterOpacity)
    case .transcribing, .processing:
      NSColor(red: 0.95, green: 0.7, blue: 0.15, alpha: masterOpacity)
    case .done:
      NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: masterOpacity)
    case .error:
      NSColor(red: 0.7, green: 0.15, blue: 0.15, alpha: masterOpacity)
    }

    ctx.setFillColor(color.cgColor)
    ctx.fill(barRect)
  }

  private func drawAudioLevel(in ctx: CGContext) {
    let barX: CGFloat = 16
    let barY: CGFloat = bounds.height - 50
    let maxWidth: CGFloat = bounds.width - 32
    let barH: CGFloat = 6
    let level = CGFloat(min(max(audioLevel, 0), 1))

    // Background.
    let bgRect = NSRect(x: barX, y: barY, width: maxWidth, height: barH)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.1 * masterOpacity).cgColor)
    ctx.fill(bgRect)

    // Level.
    let lvlRect = NSRect(x: barX, y: barY, width: maxWidth * level, height: barH)
    ctx.setFillColor(NSColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.8 * masterOpacity).cgColor)
    ctx.fill(lvlRect)
  }

  private func drawProgressBar(in ctx: CGContext) {
    let barX: CGFloat = 16
    let barY: CGFloat = bounds.height - 50
    let maxWidth: CGFloat = bounds.width - 32
    let barH: CGFloat = 4

    let bgRect = NSRect(x: barX, y: barY, width: maxWidth, height: barH)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.1 * masterOpacity).cgColor)
    ctx.fill(bgRect)

    let prog = CGFloat(min(max(progressValue, 0), 1))
    let progRect = NSRect(x: barX, y: barY, width: maxWidth * prog, height: barH)
    ctx.setFillColor(NSColor(red: 0.95, green: 0.7, blue: 0.15, alpha: 0.8 * masterOpacity).cgColor)
    ctx.fill(progRect)
  }

  private func drawLabel() {
    guard !labelText.isEmpty else { return }

    let labelColor = isDark
      ? NSColor.white.withAlphaComponent(0.95 * masterOpacity)
      : NSColor.black.withAlphaComponent(0.90 * masterOpacity)

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
      .foregroundColor: labelColor,
    ]

    let labelRect = NSRect(x: 16, y: bounds.height - 24, width: bounds.width - 80, height: 16)
    (labelText as NSString).draw(in: labelRect, withAttributes: attrs)

    // Elapsed text to the right of label.
    if !elapsedText.isEmpty {
      let elapsedColor = isDark
        ? NSColor.white.withAlphaComponent(0.5 * masterOpacity)
        : NSColor.black.withAlphaComponent(0.5 * masterOpacity)

      let elapsedAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        .foregroundColor: elapsedColor,
      ]

      let elapsedRect = NSRect(x: bounds.width - 80, y: bounds.height - 24, width: 60, height: 16)
      (elapsedText as NSString).draw(in: elapsedRect, withAttributes: elapsedAttrs)
    }
  }

  private func drawErrorMessage(_ message: String) {
    let textColor = NSColor(red: 0.9, green: 0.3, blue: 0.3, alpha: masterOpacity)

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byWordWrapping

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 12, weight: .regular),
      .foregroundColor: textColor,
      .paragraphStyle: paragraphStyle,
    ]

    let textRect = NSRect(x: 16, y: 12, width: bounds.width - 32, height: bounds.height - 60)
    (message as NSString).draw(in: textRect, withAttributes: attrs)
  }

  private func drawRetryButton(in ctx: CGContext) {
    let btnW: CGFloat = 60
    let btnH: CGFloat = 24
    let btnX = bounds.width - btnW - 12
    let btnY: CGFloat = 10
    let btnRect = NSRect(x: btnX, y: btnY, width: btnW, height: btnH)

    let bgColor = NSColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 0.2 * masterOpacity)
    let cornerPath = CGPath(roundedRect: btnRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
    ctx.addPath(cornerPath)
    ctx.setFillColor(bgColor.cgColor)
    ctx.fillPath()

    let textColor = isDark
      ? NSColor.white.withAlphaComponent(0.8 * masterOpacity)
      : NSColor.black.withAlphaComponent(0.8 * masterOpacity)

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .medium),
      .foregroundColor: textColor,
    ]
    let textSize = ("Retry" as NSString).size(withAttributes: attrs)
    let textX = btnX + (btnW - textSize.width) / 2
    let textY = btnY + (btnH - textSize.height) / 2
    ("Retry" as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
  }

  private func drawTranscript() {
    guard !transcriptText.isEmpty else { return }

    let textColor = isDark
      ? NSColor.white.withAlphaComponent(0.85 * masterOpacity)
      : NSColor.black.withAlphaComponent(0.85 * masterOpacity)

    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineBreakMode = .byTruncatingTail

    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .regular),
      .foregroundColor: textColor,
      .paragraphStyle: paragraphStyle,
    ]

    let textRect = NSRect(x: 16, y: 12, width: bounds.width - 48, height: bounds.height - 48)
    (transcriptText as NSString).draw(in: textRect, withAttributes: attrs)
  }

  private func drawCloseButton(in ctx: CGContext) {
    let btnSize: CGFloat = 20
    let btnX = bounds.width - btnSize - 8
    let btnY = bounds.height - btnSize - 8
    let btnRect = NSRect(x: btnX, y: btnY, width: btnSize, height: btnSize)

    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5 * masterOpacity).cgColor)
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)

    let inset: CGFloat = 5
    ctx.move(to: NSPoint(x: btnRect.minX + inset, y: btnRect.minY + inset))
    ctx.addLine(to: NSPoint(x: btnRect.maxX - inset, y: btnRect.maxY - inset))
    ctx.move(to: NSPoint(x: btnRect.maxX - inset, y: btnRect.minY + inset))
    ctx.addLine(to: NSPoint(x: btnRect.minX + inset, y: btnRect.maxY - inset))
    ctx.strokePath()
  }

  // MARK: - Hit Testing

  private var closeButtonRect: NSRect {
    let btnSize: CGFloat = 30 // Larger hit area than visual.
    return NSRect(
      x: bounds.width - btnSize - 4,
      y: bounds.height - btnSize - 4,
      width: btnSize,
      height: btnSize
    )
  }

  private var retryButtonRect: NSRect {
    let btnW: CGFloat = 60
    let btnH: CGFloat = 24
    return NSRect(
      x: bounds.width - btnW - 12,
      y: 6,
      width: btnW,
      height: btnH + 8
    )
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    isDragging = false
    dragStart = event.locationInWindow

    let local = convert(event.locationInWindow, from: nil)
    if closeButtonRect.contains(local) || (showRetry && retryButtonRect.contains(local)) {
      return
    }
  }

  override func mouseDragged(with event: NSEvent) {
    let current = event.locationInWindow
    let dx = current.x - dragStart.x
    let dy = current.y - dragStart.y
    if !isDragging && (dx * dx + dy * dy) > 9 { isDragging = true }

    if isDragging, let panel = window {
      var origin = panel.frame.origin
      origin.x += dx
      origin.y += dy
      panel.setFrameOrigin(origin)
    }
  }

  override func mouseUp(with event: NSEvent) {
    let local = convert(event.locationInWindow, from: nil)

    if closeButtonRect.contains(local) && !isDragging {
      onCloseClicked?()
    } else if showRetry && retryButtonRect.contains(local) && !isDragging {
      onRetryClicked?()
    } else if isDragging, let panel = window {
      let origin = panel.frame.origin
      onDragEnded?(origin.x, origin.y)
    } else {
      onBodyClicked?()
    }
    isDragging = false
  }

  override func rightMouseUp(with event: NSEvent) {
    guard !contextMenuItems.isEmpty else { return }

    let menu = NSMenu()
    for item in contextMenuItems {
      guard let id = item["id"] as? String,
            let title = item["label"] as? String else { continue }
      let menuItem = NSMenuItem(title: title, action: #selector(contextMenuAction(_:)), keyEquivalent: "")
      menuItem.target = self
      menuItem.representedObject = id
      menu.addItem(menuItem)
    }
    NSMenu.popUpContextMenu(menu, with: event, for: self)
  }

  @objc private func contextMenuAction(_ sender: NSMenuItem) {
    guard let id = sender.representedObject as? String else { return }
    onContextMenu?(id)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
