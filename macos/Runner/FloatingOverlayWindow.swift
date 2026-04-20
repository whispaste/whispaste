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

    // Note: Windows does NOT draw an accent bar at the top of the overlay pill.
    // Only the bottom progress bar is rendered (inside drawNormalContent).

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

  // MARK: - Normal Content (380×64) — matches Windows RenderNormal single-row layout

  private func drawNormalContent(ctx: CGContext, pill: NSRect, theme: ThemeColors, accent: GradientPair) {
    let now = CACurrentMediaTime()
    // Windows: content_h = pillHeight - progressBarH; cy = content_h / 2
    let progressBarH: CGFloat = 4
    let contentH = pill.height - progressBarH
    let cy = pill.minY + progressBarH + contentH / 2

    // --- Close button (left, 36×36 circle) ---
    let closeX = pill.minX + kPadH
    drawCloseButton(ctx: ctx, cx: closeX + kCloseSize / 2, cy: cy, size: kCloseSize, theme: theme)
    var x = closeX + kCloseSize + 14 // kPillGap=14

    // --- Right boundary (reserve for stop button during recording) ---
    let rightEdge: CGFloat
    if recordingState == .recording || recordingState == .listening {
      rightEdge = pill.maxX - kPadH - kStopBtnSize - 22 // kWfStopGap=22
    } else {
      rightEdge = pill.maxX - kPadH
    }

    // --- Phase-specific center content (single horizontal row) ---
    switch recordingState {
    case .recording, .listening:
      // Phase dot (8×8 pulsing)
      drawStateDot(ctx: ctx, x: x, cy: cy, accent: accent, now: now)
      x += kDotSize + kDotTextGap

      // Timer text (bold 15px, tabular figures)
      if !elapsedText.isEmpty {
        drawText(
          elapsedText,
          x: x, cy: cy, maxWidth: 55,
          font: .monospacedDigitSystemFont(ofSize: 15, weight: .bold),
          color: theme.text.withAlphaComponent(masterOpacity)
        )
      }
      x += 55 + kTimerWfGap

      // Waveform (24px height, fills remaining space)
      let wfWidth = rightEdge - x
      if wfWidth > 20 {
        drawWaveform(ctx: ctx, x: x, cy: cy, maxWidth: wfWidth, accent: accent)
      }

    case .transcribing, .processing:
      // Spinner (16×16) — uses theme accent color (cyan), not state color (amber)
      let themeAccent = isDark
        ? NSColor(red: 0x38 / 255.0, green: 0xD9 / 255.0, blue: 0xF0 / 255.0, alpha: 1)
        : NSColor(red: 0x08 / 255.0, green: 0x87 / 255.0, blue: 0xA8 / 255.0, alpha: 1)
      drawSpinner(ctx: ctx, cx: x + kSpinnerSize / 2, cy: cy, now: now,
                  color: themeAccent.withAlphaComponent(masterOpacity))
      x += kSpinnerSize + kDotTextGap

      // Label ("Transcribing…" etc.) — accent color, semibold 13px
      let displayLabel = labelText.isEmpty ? stateLabel() : labelText
      drawText(
        displayLabel,
        x: x, cy: cy, maxWidth: 110,
        font: .systemFont(ofSize: 13, weight: .semibold),
        color: themeAccent.withAlphaComponent(masterOpacity)
      )
      x += 100 + 6

      // Elapsed time — muted, 12px
      if !elapsedText.isEmpty {
        drawText(
          elapsedText,
          x: x, cy: cy, maxWidth: 45,
          font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
          color: theme.secondaryText.withAlphaComponent(masterOpacity)
        )
      }

    case .done:
      // Lucide circleCheck (16px) — success color
      let successColor = isDark
        ? NSColor(red: 0x36 / 255.0, green: 0xD9 / 255.0, blue: 0x8B / 255.0, alpha: masterOpacity)
        : NSColor(red: 0x05 / 255.0, green: 0x87 / 255.0, blue: 0x5C / 255.0, alpha: masterOpacity)
      drawCheckCircle(ctx: ctx, x: x, cy: cy, size: 16, color: successColor)
      x += 16 + kDotTextGap

      // Done message — success color, semibold
      let doneMsg = labelText.isEmpty ? "Done" : labelText
      drawText(
        doneMsg,
        x: x, cy: cy, maxWidth: rightEdge - x,
        font: .systemFont(ofSize: 13, weight: .semibold),
        color: successColor
      )

    case .error:
      // Lucide circleAlert (16px) — error color
      let errorColor = isDark
        ? NSColor(red: 0xFF / 255.0, green: 0x7B / 255.0, blue: 0x7B / 255.0, alpha: masterOpacity)
        : NSColor(red: 0xCC / 255.0, green: 0x1C / 255.0, blue: 0x1C / 255.0, alpha: masterOpacity)
      drawAlertCircle(ctx: ctx, x: x, cy: cy, size: 16, color: errorColor)
      x += 16 + kDotTextGap

      // Error message
      let errMsg = errorMessage ?? labelText
      drawText(
        errMsg,
        x: x, cy: cy, maxWidth: rightEdge - x,
        font: .systemFont(ofSize: 13, weight: .medium),
        color: errorColor
      )

    case .idle:
      break
    }

    // --- Stop button (right side, recording only — 36×36 gradient circle) ---
    if recordingState == .recording || recordingState == .listening {
      let stopX = pill.maxX - kPadH - kStopBtnSize / 2
      drawStopButton(ctx: ctx, cx: stopX, cy: cy, size: kStopBtnSize, accent: accent)
    }

    // --- Bottom progress bar (inside pill at very bottom) ---
    drawBottomProgressBar(ctx: ctx, pill: pill, radius: pillRadius, accent: accent)
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
        x: labelX, cy: midY, maxWidth: contentMaxX - labelX,
        font: .systemFont(ofSize: 10, weight: .semibold),
        color: theme.text.withAlphaComponent(masterOpacity)
      )
    }
  }

  // MARK: - Drawing Helpers

  private func drawStateDot(ctx: CGContext, x: CGFloat, cy: CGFloat, accent: GradientPair, now: CFTimeInterval) {
    // Fixed recording dot color matching Flutter RecordingPill (0xFF5252)
    // Windows: alpha pulses 45%–100% using PingPong + EaseInOut over 900ms
    var alpha: CGFloat = 1.0
    if recordingState == .recording || recordingState == .listening {
      let elapsed = now - animOrigin
      let period: Double = 0.9 // kDotPulseMs = 900
      let t = CGFloat(elapsed.truncatingRemainder(dividingBy: period) / period)
      let pingPong = t < 0.5 ? t * 2 : 2 - t * 2
      let eased = pingPong * pingPong * (3 - 2 * pingPong) // smoothstep
      alpha = 0.45 + 0.55 * eased
    }

    let dotRect = NSRect(x: x, y: cy - kDotSize / 2, width: kDotSize, height: kDotSize)
    let dotColor = NSColor(red: 0xFF / 255.0, green: 0x52 / 255.0, blue: 0x52 / 255.0, alpha: alpha * masterOpacity)
    ctx.setFillColor(dotColor.cgColor)
    ctx.fillEllipse(in: dotRect)
  }

  private func drawCloseButton(ctx: CGContext, cx: CGFloat, cy: CGFloat, size: CGFloat, theme: ThemeColors) {
    // Subtle circle background (matches close button idle state)
    let circleRect = NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
    ctx.setFillColor(theme.secondaryText.withAlphaComponent(0.06 * masterOpacity).cgColor)
    ctx.fillEllipse(in: circleRect)

    // ✕ icon — Windows: pad = size * 0.375 (Lucide X spans 6→18 in 24px)
    let pad = size * 0.375
    let x0 = cx - size / 2 + pad
    let y0 = cy - size / 2 + pad
    let x1 = cx + size / 2 - pad
    let y1 = cy + size / 2 - pad
    ctx.setStrokeColor(theme.secondaryText.withAlphaComponent(0.7 * masterOpacity).cgColor)
    ctx.setLineWidth(2)
    ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: x0, y: y0))
    ctx.addLine(to: CGPoint(x: x1, y: y1))
    ctx.move(to: CGPoint(x: x1, y: y0))
    ctx.addLine(to: CGPoint(x: x0, y: y1))
    ctx.strokePath()
  }

  private func drawStopButton(ctx: CGContext, cx: CGFloat, cy: CGFloat, size: CGFloat, accent: GradientPair) {
    // Windows: solid gradient-filled red circle with white square outline inside
    let circleRect = NSRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)

    // Gradient circle background (matches _PillStopButton)
    ctx.saveGState()
    ctx.addEllipse(in: circleRect)
    ctx.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(
      colorsSpace: colorSpace,
      colors: [accent.c0.withAlphaComponent(masterOpacity).cgColor,
               accent.c1.withAlphaComponent(masterOpacity).cgColor] as CFArray,
      locations: [0, 1]
    ) {
      ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: circleRect.minX, y: circleRect.maxY),
        end: CGPoint(x: circleRect.maxX, y: circleRect.minY),
        options: []
      )
    }
    ctx.restoreGState()

    // White square OUTLINE (Lucide square — stroked, not filled)
    let iconSize = size * 0.39 // kStopIconSize=14 / kStopBtnSize=36 ≈ 0.39
    let iconRect = NSRect(x: cx - iconSize / 2, y: cy - iconSize / 2, width: iconSize, height: iconSize)
    let iconPath = CGPath(roundedRect: iconRect, cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
    ctx.addPath(iconPath)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(masterOpacity).cgColor)
    ctx.setLineWidth(2)
    ctx.setLineJoin(.round)
    ctx.strokePath()
  }

  private func drawWaveform(ctx: CGContext, x: CGFloat, cy: CGFloat, maxWidth: CGFloat, accent: GradientPair) {
    let totalWidth = CGFloat(kBarCount) * kBarWidth + CGFloat(kBarCount - 1) * kBarGap
    let maxH: CGFloat = isCompact ? 16 : 24
    // Center bars in available width (matching Windows)
    let startX = x + (maxWidth - totalWidth) / 2

    guard totalWidth <= maxWidth else { return }

    // Windows waveform colors (dark theme):
    // active: 85% accent (#38D9F0), muted: 50% textMuted (#8A99B2)
    let activeColor = isDark
      ? NSColor(red: 0x38 / 255.0, green: 0xD9 / 255.0, blue: 0xF0 / 255.0, alpha: 0.85 * masterOpacity)
      : NSColor(red: 0x08 / 255.0, green: 0x87 / 255.0, blue: 0xA8 / 255.0, alpha: 0.85 * masterOpacity)
    let mutedColor = isDark
      ? NSColor(red: 0x8A / 255.0, green: 0x99 / 255.0, blue: 0xB2 / 255.0, alpha: 0.5 * masterOpacity)
      : NSColor(red: 0x5B / 255.0, green: 0x69 / 255.0, blue: 0x7E / 255.0, alpha: 0.5 * masterOpacity)

    for i in 0..<kBarCount {
      let level = waveDisplay[i] / maxH // Normalize to 0-1
      let barH = max(4, waveDisplay[i]) // 4px min (matching Windows)
      let bx = startX + CGFloat(i) * (kBarWidth + kBarGap)
      let by = cy - barH / 2
      let barRect = NSRect(x: bx, y: by, width: kBarWidth, height: barH)
      let barPath = CGPath(roundedRect: barRect, cornerWidth: kBarWidth / 2, cornerHeight: kBarWidth / 2, transform: nil)

      // Color based on level: >0.30 = active, else muted
      let color = level > 0.30 ? activeColor : mutedColor
      ctx.setFillColor(color.cgColor)
      ctx.addPath(barPath)
      ctx.fillPath()
    }
  }

  private func drawSpinner(ctx: CGContext, cx: CGFloat, cy: CGFloat, now: CFTimeInterval, accent: GradientPair) {
    drawSpinner(ctx: ctx, cx: cx, cy: cy, now: now, color: accent.c0.withAlphaComponent(0.8 * masterOpacity))
  }

  private func drawSpinner(ctx: CGContext, cx: CGFloat, cy: CGFloat, now: CFTimeInterval, color: NSColor) {
    let elapsed = now - animOrigin
    let angle = CGFloat(elapsed.truncatingRemainder(dividingBy: 0.75) / 0.75) * .pi * 2
    let arcLen: CGFloat = .pi * 1.5 // 270° (matching Windows)

    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(2)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: cx, y: cy), radius: kSpinnerSize / 2, startAngle: angle, endAngle: angle + arcLen, clockwise: false)
    ctx.strokePath()
  }

  private func drawText(
    _ text: String,
    x: CGFloat, cy: CGFloat, maxWidth: CGFloat,
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

    // Vertically center text at cy using font metrics
    let lineHeight = font.ascender - font.descender + font.leading
    let textRect = NSRect(x: x, y: cy - lineHeight / 2 + font.descender, width: maxWidth, height: lineHeight)
    (text as NSString).draw(in: textRect, withAttributes: attrs)
  }

  /// Lucide circle-check icon (matching Windows PaintNormal kDone).
  private func drawCheckCircle(ctx: CGContext, x: CGFloat, cy: CGFloat, size: CGFloat, color: NSColor) {
    let sc = size / 24.0
    let ix = x, iy = cy - size / 2
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)
    // Circle
    ctx.addEllipse(in: NSRect(x: ix + 2 * sc, y: iy + 2 * sc, width: 20 * sc, height: 20 * sc))
    ctx.strokePath()
    // Checkmark: (9,12)→(11,14)→(15,10) in 24×24 space
    ctx.move(to: CGPoint(x: ix + 9 * sc, y: iy + (24 - 12) * sc))
    ctx.addLine(to: CGPoint(x: ix + 11 * sc, y: iy + (24 - 14) * sc))
    ctx.addLine(to: CGPoint(x: ix + 15 * sc, y: iy + (24 - 10) * sc))
    ctx.strokePath()
  }

  /// Lucide circle-alert icon (matching Windows PaintNormal kError).
  private func drawAlertCircle(ctx: CGContext, x: CGFloat, cy: CGFloat, size: CGFloat, color: NSColor) {
    let sc = size / 24.0
    let ix = x, iy = cy - size / 2
    ctx.setStrokeColor(color.cgColor)
    ctx.setLineWidth(1.5)
    ctx.setLineCap(.round)
    // Circle
    ctx.addEllipse(in: NSRect(x: ix + 2 * sc, y: iy + 2 * sc, width: 20 * sc, height: 20 * sc))
    ctx.strokePath()
    // Exclamation line: (12,8)→(12,12) → in Y-up: (12, 16)→(12, 12)
    ctx.move(to: CGPoint(x: ix + 12 * sc, y: iy + (24 - 8) * sc))
    ctx.addLine(to: CGPoint(x: ix + 12 * sc, y: iy + (24 - 12) * sc))
    ctx.strokePath()
    // Dot at (12, 16) → in Y-up: (12, 8)
    ctx.setFillColor(color.cgColor)
    ctx.fillEllipse(in: NSRect(x: ix + 11.25 * sc, y: iy + (24 - 16.75) * sc, width: 1.5 * sc, height: 1.5 * sc))
  }

  /// Bottom progress bar inside pill (matching Windows PaintBottomProgressBar).
  private func drawBottomProgressBar(ctx: CGContext, pill: NSRect, radius: CGFloat, accent: GradientPair) {
    let barH: CGFloat = 4
    let barY = pill.minY // Bottom of pill in NSView Y-up

    ctx.saveGState()
    // Clip to pill shape
    let clipPath = CGPath(roundedRect: pill, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(clipPath)
    ctx.clip()

    // Clip to bar region
    let barRegion = NSRect(x: pill.minX, y: barY, width: pill.width, height: barH)
    ctx.clip(to: barRegion)

    switch recordingState {
    case .recording, .listening:
      if progressValue > 0 {
        // Time-limited recording progress bar
        let prog = CGFloat(min(max(progressValue, 0), 1))
        let fillW = pill.width * prog
        var fillColor: NSColor
        if prog >= 0.90 {
          fillColor = NSColor(red: 0xFF / 255.0, green: 0x52 / 255.0, blue: 0x52 / 255.0, alpha: masterOpacity)
        } else if prog >= 0.75 {
          fillColor = NSColor(red: 0xFF / 255.0, green: 0xC1 / 255.0, blue: 0x07 / 255.0, alpha: masterOpacity)
        } else {
          let tc = themeColors(dark: isDark)
          fillColor = tc.text.withAlphaComponent(masterOpacity)
        }
        ctx.setFillColor(fillColor.cgColor)
        ctx.fill(NSRect(x: pill.minX, y: barY, width: fillW, height: barH))
      } else {
        // Unlimited — subtle accent line
        let themeAccent = isDark
          ? NSColor(red: 0x38 / 255.0, green: 0xD9 / 255.0, blue: 0xF0 / 255.0, alpha: 0.3 * masterOpacity)
          : NSColor(red: 0x08 / 255.0, green: 0x87 / 255.0, blue: 0xA8 / 255.0, alpha: 0.3 * masterOpacity)
        ctx.setFillColor(themeAccent.cgColor)
        ctx.fill(NSRect(x: pill.minX, y: barY, width: pill.width, height: barH))
      }

    case .transcribing, .processing:
      // Shimmer bar (accent color sweep)
      let elapsed = CACurrentMediaTime() - animOrigin
      let period: Double = 1.2
      let t = CGFloat(elapsed.truncatingRemainder(dividingBy: period) / period)
      let sweep = -0.3 + t * 1.6

      // Base
      let themeAccent = isDark
        ? NSColor(red: 0x38 / 255.0, green: 0xD9 / 255.0, blue: 0xF0 / 255.0, alpha: 0.15 * masterOpacity)
        : NSColor(red: 0x08 / 255.0, green: 0x87 / 255.0, blue: 0xA8 / 255.0, alpha: 0.12 * masterOpacity)
      ctx.setFillColor(themeAccent.cgColor)
      ctx.fill(barRegion)

      // Glow sweep
      let glowW = pill.width * 0.3
      let glowX = pill.minX + sweep * pill.width - glowW / 2
      let glowAccent = isDark
        ? NSColor(red: 0x38 / 255.0, green: 0xD9 / 255.0, blue: 0xF0 / 255.0, alpha: 0.6 * masterOpacity)
        : NSColor(red: 0x08 / 255.0, green: 0x87 / 255.0, blue: 0xA8 / 255.0, alpha: 0.5 * masterOpacity)
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      if let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [NSColor.clear.cgColor, glowAccent.cgColor, NSColor.clear.cgColor] as CFArray,
        locations: [0, 0.5, 1]
      ) {
        ctx.drawLinearGradient(
          gradient,
          start: CGPoint(x: glowX, y: barY),
          end: CGPoint(x: glowX + glowW, y: barY),
          options: []
        )
      }

    case .done:
      // Solid green bar
      let green = isDark
        ? NSColor(red: 0x16 / 255.0, green: 0xA3 / 255.0, blue: 0x4A / 255.0, alpha: 0.8 * masterOpacity)
        : NSColor(red: 0x16 / 255.0, green: 0xA3 / 255.0, blue: 0x4A / 255.0, alpha: 0.7 * masterOpacity)
      ctx.setFillColor(green.cgColor)
      ctx.fill(barRegion)

    case .error, .idle:
      break
    }

    ctx.restoreGState()
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
