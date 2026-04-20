import Cocoa
import FlutterMacOS

/// NSPanel subclass for the floating overlay — non-activating, always-on-top.
class FloatingOverlayPanel: NSPanel {
  init(width: CGFloat = 380, height: CGFloat = 64) {
    // Add shadow padding so multi-layer shadows render cleanly.
    let padded = NSRect(x: 100, y: 100, width: width + 56, height: height + 56)
    super.init(
      contentRect: padded,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false // We render our own shadows.
    isMovableByWindowBackground = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Recording state the overlay displays.
enum OverlayRecordingState: String {
  case idle, listening, recording, transcribing, processing, done, error
}

// MARK: - Layout Constants (match Windows floating_overlay_window.cpp)

private let kNormalWidth: CGFloat = 380
private let kNormalHeight: CGFloat = 64
private let kCompactWidth: CGFloat = 280
private let kCompactHeight: CGFloat = 40
private let kCornerRadius: CGFloat = 32
private let kCompactRadius: CGFloat = 20
private let kAccentBarH: CGFloat = 4
private let kShadowPad: CGFloat = 28
private let kPadH: CGFloat = 16
private let kBarWidth: CGFloat = 2.5
private let kBarGap: CGFloat = 1.5
private let kBarCount = 12
private let kCloseSize: CGFloat = 36
private let kCompactCloseSize: CGFloat = 28
private let kStopBtnSize: CGFloat = 36
private let kCompactStopSize: CGFloat = 28
private let kDotSize: CGFloat = 8
private let kDotTextGap: CGFloat = 8
private let kTimerWfGap: CGFloat = 18
private let kSpinnerSize: CGFloat = 16
private let kAnimInterval: TimeInterval = 1.0 / 30.0 // ~30 fps

// MARK: - Accent Gradient Colors per State (match Windows AccentColorsFor)

private struct GradientPair {
  let c0: NSColor
  let c1: NSColor
}

private func accentColors(for state: OverlayRecordingState) -> GradientPair {
  switch state {
  case .recording, .listening:
    return GradientPair(
      c0: NSColor(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0, alpha: 1),
      c1: NSColor(red: 0xDC / 255.0, green: 0x26 / 255.0, blue: 0x26 / 255.0, alpha: 1)
    )
  case .transcribing, .processing:
    return GradientPair(
      c0: NSColor(red: 0xF5 / 255.0, green: 0x9E / 255.0, blue: 0x0B / 255.0, alpha: 1),
      c1: NSColor(red: 0xD9 / 255.0, green: 0x77 / 255.0, blue: 0x06 / 255.0, alpha: 1)
    )
  case .done:
    return GradientPair(
      c0: NSColor(red: 0x22 / 255.0, green: 0xC5 / 255.0, blue: 0x5E / 255.0, alpha: 1),
      c1: NSColor(red: 0x16 / 255.0, green: 0xA3 / 255.0, blue: 0x4A / 255.0, alpha: 1)
    )
  case .error:
    return GradientPair(
      c0: NSColor(red: 0xEF / 255.0, green: 0x44 / 255.0, blue: 0x44 / 255.0, alpha: 1),
      c1: NSColor(red: 0xB9 / 255.0, green: 0x1C / 255.0, blue: 0x1C / 255.0, alpha: 1)
    )
  case .idle:
    return GradientPair(
      c0: NSColor(red: 0x14 / 255.0, green: 0xB8 / 255.0, blue: 0xD4 / 255.0, alpha: 1),
      c1: NSColor(red: 0x0A / 255.0, green: 0x99 / 255.0, blue: 0xB8 / 255.0, alpha: 1)
    )
  }
}

// MARK: - Theme Colors (match Windows GetThemeColors)

private struct ThemeColors {
  let surface: NSColor
  let text: NSColor
  let secondaryText: NSColor
  let border: NSColor
}

private func themeColors(dark: Bool) -> ThemeColors {
  if dark {
    return ThemeColors(
      surface: NSColor(red: 0x14 / 255.0, green: 0x19 / 255.0, blue: 0x26 / 255.0, alpha: 1),
      text: NSColor(red: 0xF0 / 255.0, green: 0xF4 / 255.0, blue: 0xFA / 255.0, alpha: 1),
      secondaryText: NSColor(red: 0x8A / 255.0, green: 0x99 / 255.0, blue: 0xB2 / 255.0, alpha: 1),
      border: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.08)
    )
  } else {
    return ThemeColors(
      surface: NSColor(red: 0xF0 / 255.0, green: 0xF3 / 255.0, blue: 0xF7 / 255.0, alpha: 1),
      text: NSColor(red: 0x10 / 255.0, green: 0x18 / 255.0, blue: 0x28 / 255.0, alpha: 1),
      secondaryText: NSColor(red: 0x5B / 255.0, green: 0x69 / 255.0, blue: 0x7E / 255.0, alpha: 1),
      border: NSColor(red: 0x0F / 255.0, green: 0x17 / 255.0, blue: 0x2A / 255.0, alpha: 0.08)
    )
  }
}

/// Main view for the floating overlay — pill-shaped to match the Windows overlay.
///
/// Renders a premium pill UI with accent gradient bar, waveform bars, state dot,
/// label + timer text, close/stop buttons, and smooth animations.
class FloatingOverlayView: NSView {
  // MARK: - Public State

  var recordingState: OverlayRecordingState = .idle { didSet { onStateChange() } }
  var labelText: String = "" { didSet { needsDisplay = true } }
  var transcriptText: String = "" { didSet { needsDisplay = true } }
  var elapsedText: String = "" { didSet { needsDisplay = true } }
  var hintText: String = "" { didSet { needsDisplay = true } }
  var errorMessage: String? { didSet { needsDisplay = true } }
  var showRetry: Bool = false { didSet { needsDisplay = true } }
  var audioLevel: Float = 0 { didSet { updateWaveformTarget() } }
  var progressValue: Double = 0 { didSet { needsDisplay = true } }
  var masterOpacity: CGFloat = 1.0 { didSet { needsDisplay = true } }
  var isDark: Bool = true { didSet { needsDisplay = true } }
  var isCompact: Bool = false { didSet { resizePill(); needsDisplay = true } }
  var contextMenuItems: [[String: Any]] = []

  // MARK: - Callbacks

  var onDragEnded: ((_ x: CGFloat, _ y: CGFloat) -> Void)?
  var onCloseClicked: (() -> Void)?
  var onBodyClicked: (() -> Void)?
  var onRetryClicked: (() -> Void)?
  var onContextMenu: ((_ itemId: String) -> Void)?

  // MARK: - Internal Animation State

  private var isDragging = false
  private var dragStart: NSPoint = .zero
  private var animTimer: Timer?
  private var animOrigin: CFTimeInterval = CACurrentMediaTime()

  // Waveform bars — 12 bars with smooth interpolation.
  private var waveTarget: [CGFloat] = Array(repeating: 0, count: kBarCount)
  private var waveDisplay: [CGFloat] = Array(repeating: 0, count: kBarCount)

  // MARK: - Lifecycle

  override init(frame: NSRect) {
    super.init(frame: frame)
    startAnimation()
  }

  required init?(coder: NSCoder) {
    super.init(coder: coder)
    startAnimation()
  }

  deinit {
    animTimer?.invalidate()
  }

  private func startAnimation() {
    animTimer = Timer.scheduledTimer(withTimeInterval: kAnimInterval, repeats: true) { [weak self] _ in
      self?.tick()
    }
  }

  private func tick() {
    // Interpolate waveform bars toward targets.
    var changed = false
    for i in 0..<kBarCount {
      let diff = waveTarget[i] - waveDisplay[i]
      if abs(diff) > 0.1 {
        waveDisplay[i] += diff * 0.3
        changed = true
      }
    }
    if changed || recordingState == .recording || recordingState == .listening
        || recordingState == .transcribing || recordingState == .processing {
      needsDisplay = true
    }
  }

  private func onStateChange() {
    animOrigin = CACurrentMediaTime()
    if recordingState != .recording && recordingState != .listening {
      waveTarget = Array(repeating: 0, count: kBarCount)
    }
    needsDisplay = true
  }

  private func updateWaveformTarget() {
    let level = CGFloat(min(max(audioLevel, 0), 1))
    for i in 0..<kBarCount {
      let base = level * 24
      let variation = CGFloat(sin(Double(i) * 0.8 + CACurrentMediaTime() * 3)) * 0.3 + 0.7
      waveTarget[i] = max(2, base * variation)
    }
  }

  private func resizePill() {
    let w = isCompact ? kCompactWidth : kNormalWidth
    let h = isCompact ? kCompactHeight : kNormalHeight
    let totalW = w + kShadowPad * 2
    let totalH = h + kShadowPad * 2
    if let panel = window {
      var frame = panel.frame
      frame.size = NSSize(width: totalW, height: totalH)
      panel.setFrame(frame, display: true)
    }
    self.frame = NSRect(x: 0, y: 0, width: totalW, height: totalH)
  }

  // MARK: - Pill Geometry

  private var pillWidth: CGFloat { isCompact ? kCompactWidth : kNormalWidth }
  private var pillHeight: CGFloat { isCompact ? kCompactHeight : kNormalHeight }
  private var pillRadius: CGFloat { isCompact ? kCompactRadius : kCornerRadius }
  private var pillRect: NSRect {
    NSRect(x: kShadowPad, y: kShadowPad, width: pillWidth, height: pillHeight)
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.clear(bounds)

    let pill = pillRect
    let radius = pillRadius
    let theme = themeColors(dark: isDark)
    let accent = accentColors(for: recordingState)

    drawShadow(ctx: ctx, pill: pill, radius: radius)

    let bgPath = CGPath(roundedRect: pill, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(bgPath)
    ctx.setFillColor(theme.surface.withAlphaComponent(0.96 * masterOpacity).cgColor)
    ctx.fillPath()

    drawAccentBar(ctx: ctx, pill: pill, radius: radius, accent: accent)

    if recordingState == .transcribing || recordingState == .processing {
      drawProgressBar(ctx: ctx, pill: pill, accent: accent)
    }

    if isCompact {
      drawCompactContent(ctx: ctx, pill: pill, theme: theme, accent: accent)
    } else {
      drawNormalContent(ctx: ctx, pill: pill, theme: theme, accent: accent)
    }

    ctx.addPath(bgPath)
    ctx.setStrokeColor(theme.border.withAlphaComponent(0.15 * masterOpacity).cgColor)
    ctx.setLineWidth(0.5)
    ctx.strokePath()
  }

  // MARK: - Shadow

  private func drawShadow(ctx: CGContext, pill: NSRect, radius: CGFloat) {
    let shadowColor = isDark
      ? NSColor.black.withAlphaComponent(0.03 * masterOpacity)
      : NSColor.black.withAlphaComponent(0.02 * masterOpacity)

    for i in 0..<8 {
      let spread = CGFloat(i) * 1.5
      let offsetY: CGFloat = CGFloat(i) * 0.8
      let inflated = pill.insetBy(dx: -spread, dy: -spread).offsetBy(dx: 0, dy: -offsetY)
      let path = CGPath(roundedRect: inflated, cornerWidth: radius + spread, cornerHeight: radius + spread, transform: nil)
      ctx.addPath(path)
      ctx.setFillColor(shadowColor.cgColor)
      ctx.fillPath()
    }
  }

  // MARK: - Accent Gradient Bar

  private func drawAccentBar(ctx: CGContext, pill: NSRect, radius: CGFloat, accent: GradientPair) {
    ctx.saveGState()

    let clipPath = CGMutablePath()
    clipPath.addRoundedRect(in: pill, cornerWidth: radius, cornerHeight: radius)
    ctx.addPath(clipPath)
    ctx.clip()

    let barRect = NSRect(x: pill.minX, y: pill.minY, width: pill.width, height: kAccentBarH)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(
      colorsSpace: colorSpace,
      colors: [accent.c0.withAlphaComponent(masterOpacity).cgColor,
               accent.c1.withAlphaComponent(masterOpacity).cgColor] as CFArray,
      locations: [0, 1]
    ) {
      ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: barRect.minX, y: barRect.midY),
        end: CGPoint(x: barRect.maxX, y: barRect.midY),
        options: []
      )
    }

    ctx.restoreGState()
  }

  // MARK: - Progress Bar

  private func drawProgressBar(ctx: CGContext, pill: NSRect, accent: GradientPair) {
    let prog = CGFloat(min(max(progressValue, 0), 1))
    guard prog > 0 else { return }

    let barY = pill.minY + kAccentBarH
    let barH: CGFloat = 2
    let barRect = NSRect(x: pill.minX, y: barY, width: pill.width * prog, height: barH)
    ctx.setFillColor(accent.c0.withAlphaComponent(0.6 * masterOpacity).cgColor)
    ctx.fill(barRect)
  }

  // MARK: - Normal Content (380×64)

  private func drawNormalContent(ctx: CGContext, pill: NSRect, theme: ThemeColors, accent: GradientPair) {
    let now = CACurrentMediaTime()
    let midY = pill.midY + 2
    let closeBtnSize = kCloseSize
    let closePad: CGFloat = 8

    let closeCX = pill.minX + closePad + closeBtnSize / 2
    let closeCY = midY
    drawCloseButton(ctx: ctx, cx: closeCX, cy: closeCY, size: closeBtnSize, theme: theme)

    let contentX = pill.minX + closePad + closeBtnSize + 8
    let contentMaxX: CGFloat

    if recordingState == .recording || recordingState == .listening {
      let stopCX = pill.maxX - closePad - kStopBtnSize / 2
      let stopCY = midY
      drawStopButton(ctx: ctx, cx: stopCX, cy: stopCY, size: kStopBtnSize, accent: accent)
      contentMaxX = stopCX - kStopBtnSize / 2 - 8
    } else {
      contentMaxX = pill.maxX - kPadH
    }

    let dotY = midY + 8
    drawStateDot(ctx: ctx, x: contentX, cy: dotY, accent: accent, now: now)

    let labelX = contentX + kDotSize + kDotTextGap
    let displayLabel = labelText.isEmpty ? stateLabel() : labelText
    drawText(
      displayLabel,
      x: labelX, y: dotY - 6, maxWidth: contentMaxX - labelX - 60,
      font: .systemFont(ofSize: 12, weight: .semibold),
      color: theme.text.withAlphaComponent(masterOpacity)
    )

    if !elapsedText.isEmpty {
      drawText(
        elapsedText,
        x: contentMaxX - 50, y: dotY - 5, maxWidth: 50,
        font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular),
        color: theme.secondaryText.withAlphaComponent(masterOpacity),
        alignment: .right
      )
    }

    let vizY = midY - 12

    if recordingState == .recording || recordingState == .listening {
      drawWaveform(ctx: ctx, x: contentX, cy: vizY, maxWidth: contentMaxX - contentX, accent: accent)
    } else if recordingState == .transcribing || recordingState == .processing {
      drawSpinner(ctx: ctx, cx: contentX + 8, cy: vizY, now: now, accent: accent)
      let spinLabel = recordingState == .transcribing ? "Transcribing…" : "Processing…"
      drawText(
        spinLabel,
        x: contentX + 22, y: vizY - 5, maxWidth: contentMaxX - contentX - 30,
        font: .systemFont(ofSize: 11, weight: .regular),
        color: theme.secondaryText.withAlphaComponent(0.8 * masterOpacity)
      )
    } else if let error = errorMessage, !error.isEmpty {
      drawText(
        error,
        x: contentX, y: vizY - 5, maxWidth: contentMaxX - contentX,
        font: .systemFont(ofSize: 11, weight: .regular),
        color: NSColor(red: 0.9, green: 0.3, blue: 0.3, alpha: masterOpacity)
      )
    } else if !transcriptText.isEmpty {
      drawText(
        transcriptText,
        x: contentX, y: vizY - 5, maxWidth: contentMaxX - contentX,
        font: .systemFont(ofSize: 11, weight: .regular),
        color: theme.text.withAlphaComponent(0.85 * masterOpacity),
        lineBreak: .byTruncatingTail
      )
    }
  }

  // MARK: - Compact Content (280×40)

  private func drawCompactContent(ctx: CGContext, pill: NSRect, theme: ThemeColors, accent: GradientPair) {
    let now = CACurrentMediaTime()
    let midY = pill.midY + 1
    let closePad: CGFloat = 6

    let closeCX = pill.minX + closePad + kCompactCloseSize / 2
    drawCloseButton(ctx: ctx, cx: closeCX, cy: midY, size: kCompactCloseSize, theme: theme)

    let contentX = pill.minX + closePad + kCompactCloseSize + 6
    let contentMaxX: CGFloat

    if recordingState == .recording || recordingState == .listening {
      let stopCX = pill.maxX - closePad - kCompactStopSize / 2
      drawStopButton(ctx: ctx, cx: stopCX, cy: midY, size: kCompactStopSize, accent: accent)
      contentMaxX = stopCX - kCompactStopSize / 2 - 6
    } else {
      contentMaxX = pill.maxX - closePad
    }

    drawStateDot(ctx: ctx, x: contentX, cy: midY, accent: accent, now: now)

    let labelX = contentX + kDotSize + 6
    if recordingState == .recording || recordingState == .listening {
      drawWaveform(ctx: ctx, x: labelX, cy: midY, maxWidth: contentMaxX - labelX, accent: accent)
    } else {
      let displayLabel = labelText.isEmpty ? stateLabel() : labelText
      drawText(
        displayLabel,
        x: labelX, y: midY - 5, maxWidth: contentMaxX - labelX,
        font: .systemFont(ofSize: 10, weight: .semibold),
        color: theme.text.withAlphaComponent(masterOpacity)
      )
    }
  }

  // MARK: - Drawing Helpers

  private func drawStateDot(ctx: CGContext, x: CGFloat, cy: CGFloat, accent: GradientPair, now: CFTimeInterval) {
    let elapsed = now - animOrigin
    let isActive = recordingState == .recording || recordingState == .listening
    let pulse = isActive
      ? CGFloat(0.5 + 0.5 * sin(elapsed * 4.0))
      : CGFloat(1.0)

    let dotRect = NSRect(x: x, y: cy - kDotSize / 2, width: kDotSize, height: kDotSize)
    ctx.setFillColor(accent.c0.withAlphaComponent(pulse * masterOpacity).cgColor)
    ctx.fillEllipse(in: dotRect)
  }

  private func drawCloseButton(ctx: CGContext, cx: CGFloat, cy: CGFloat, size: CGFloat, theme: ThemeColors) {
    let circleRect = NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
    ctx.setFillColor(theme.secondaryText.withAlphaComponent(0.08 * masterOpacity).cgColor)
    ctx.fillEllipse(in: circleRect)

    let inset = size * 0.3
    ctx.setStrokeColor(theme.secondaryText.withAlphaComponent(0.6 * masterOpacity).cgColor)
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: cx - inset / 2, y: cy - inset / 2))
    ctx.addLine(to: CGPoint(x: cx + inset / 2, y: cy + inset / 2))
    ctx.move(to: CGPoint(x: cx + inset / 2, y: cy - inset / 2))
    ctx.addLine(to: CGPoint(x: cx - inset / 2, y: cy + inset / 2))
    ctx.strokePath()
  }

  private func drawStopButton(ctx: CGContext, cx: CGFloat, cy: CGFloat, size: CGFloat, accent: GradientPair) {
    let circleRect = NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
    ctx.setFillColor(accent.c0.withAlphaComponent(0.15 * masterOpacity).cgColor)
    ctx.fillEllipse(in: circleRect)

    let iconSize = size * 0.36
    let iconRect = NSRect(x: cx - iconSize / 2, y: cy - iconSize / 2, width: iconSize, height: iconSize)
    let iconPath = CGPath(roundedRect: iconRect, cornerWidth: 2, cornerHeight: 2, transform: nil)
    ctx.addPath(iconPath)
    ctx.setStrokeColor(accent.c0.withAlphaComponent(0.9 * masterOpacity).cgColor)
    ctx.setLineWidth(1.5)
    ctx.strokePath()
  }

  private func drawWaveform(ctx: CGContext, x: CGFloat, cy: CGFloat, maxWidth: CGFloat, accent: GradientPair) {
    let totalWidth = CGFloat(kBarCount) * kBarWidth + CGFloat(kBarCount - 1) * kBarGap
    let startX = x
    let maxH: CGFloat = isCompact ? 16 : 24

    guard totalWidth <= maxWidth else { return }

    ctx.setFillColor(accent.c0.withAlphaComponent(0.8 * masterOpacity).cgColor)

    for i in 0..<kBarCount {
      let barH = max(2, min(waveDisplay[i], maxH))
      let bx = startX + CGFloat(i) * (kBarWidth + kBarGap)
      let by = cy - barH / 2
      let barRect = NSRect(x: bx, y: by, width: kBarWidth, height: barH)
      let barPath = CGPath(roundedRect: barRect, cornerWidth: kBarWidth / 2, cornerHeight: kBarWidth / 2, transform: nil)
      ctx.addPath(barPath)
      ctx.fillPath()
    }
  }

  private func drawSpinner(ctx: CGContext, cx: CGFloat, cy: CGFloat, now: CFTimeInterval, accent: GradientPair) {
    let elapsed = now - animOrigin
    let angle = CGFloat(elapsed.truncatingRemainder(dividingBy: 0.75) / 0.75) * .pi * 2
    let arcLen: CGFloat = .pi * 1.6

    ctx.setStrokeColor(accent.c0.withAlphaComponent(0.8 * masterOpacity).cgColor)
    ctx.setLineWidth(2)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: kSpinnerSize / 2, startAngle: angle, endAngle: angle + arcLen, clockwise: false)
    ctx.strokePath()
  }

  private func drawText(
    _ text: String,
    x: CGFloat, y: CGFloat, maxWidth: CGFloat,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left,
    lineBreak: NSLineBreakMode = .byTruncatingTail
  ) {
    let para = NSMutableParagraphStyle()
    para.lineBreakMode = lineBreak
    para.alignment = alignment

    let attrs: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: color,
      .paragraphStyle: para,
    ]

    let textRect = NSRect(x: x, y: y, width: maxWidth, height: font.pointSize + 6)
    (text as NSString).draw(in: textRect, withAttributes: attrs)
  }

  private func stateLabel() -> String {
    switch recordingState {
    case .idle: return ""
    case .listening, .recording: return "Recording"
    case .transcribing: return "Transcribing…"
    case .processing: return "Processing…"
    case .done: return "Done"
    case .error: return "Error"
    }
  }

  // MARK: - Hit Testing

  private var closeButtonRect: NSRect {
    let size = isCompact ? kCompactCloseSize : kCloseSize
    let pad: CGFloat = isCompact ? 6 : 8
    let pill = pillRect
    let cx = pill.minX + pad + size / 2
    let cy = pill.midY + (isCompact ? 1 : 2)
    return NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
  }

  private var stopButtonRect: NSRect {
    let size = isCompact ? kCompactStopSize : kStopBtnSize
    let pad: CGFloat = isCompact ? 6 : 8
    let pill = pillRect
    let cx = pill.maxX - pad - size / 2
    let cy = pill.midY + (isCompact ? 1 : 2)
    return NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
  }

  private var retryButtonRect: NSRect {
    let btnW: CGFloat = 60
    let btnH: CGFloat = 24
    let pill = pillRect
    return NSRect(x: pill.maxX - btnW - 12, y: pill.minY + 6, width: btnW, height: btnH + 8)
  }

  // MARK: - Mouse Events

  override func mouseDown(with event: NSEvent) {
    isDragging = false
    dragStart = event.locationInWindow
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
    } else if (recordingState == .recording || recordingState == .listening)
                && stopButtonRect.contains(local) && !isDragging {
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
