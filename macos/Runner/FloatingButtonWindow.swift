import Cocoa
import FlutterMacOS

/// NSPanel subclass for the floating button — non-activating, always-on-top.
class FloatingButtonPanel: NSPanel {
  init(size: CGFloat) {
    let frame = NSRect(x: 200, y: 200, width: size, height: size)
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
    hasShadow = false // We draw our own multi-layer shadow
    isMovableByWindowBackground = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Visual state matching the Dart enum.
enum FloatingButtonVisualState: String {
  case idle, recording, transcribing, done, error, disabled
}

// MARK: - Gradient color set (matches Windows ColorsFor exactly)

private struct GradientColors {
  let top: NSColor
  let mid: NSColor
  let bot: NSColor
}

private func colorsFor(state: FloatingButtonVisualState, isDark: Bool) -> GradientColors {
  switch state {
  case .idle:
    return isDark
      ? GradientColors(
          top: NSColor(red: 0x38/255.0, green: 0xD9/255.0, blue: 0xF0/255.0, alpha: 1),
          mid: NSColor(red: 0x14/255.0, green: 0xB8/255.0, blue: 0xD4/255.0, alpha: 1),
          bot: NSColor(red: 0x0A/255.0, green: 0x99/255.0, blue: 0xB8/255.0, alpha: 1))
      : GradientColors(
          top: NSColor(red: 0x08/255.0, green: 0x91/255.0, blue: 0xB2/255.0, alpha: 1),
          mid: NSColor(red: 0x0E/255.0, green: 0x74/255.0, blue: 0x90/255.0, alpha: 1),
          bot: NSColor(red: 0x15/255.0, green: 0x5E/255.0, blue: 0x75/255.0, alpha: 1))
  case .recording:
    return GradientColors(
      top: NSColor(red: 0xEF/255.0, green: 0x44/255.0, blue: 0x44/255.0, alpha: 1),
      mid: NSColor(red: 0xE5/255.0, green: 0x35/255.0, blue: 0x35/255.0, alpha: 1),
      bot: NSColor(red: 0xDC/255.0, green: 0x26/255.0, blue: 0x26/255.0, alpha: 1))
  case .transcribing:
    return GradientColors(
      top: NSColor(red: 0xF5/255.0, green: 0x9E/255.0, blue: 0x0B/255.0, alpha: 1),
      mid: NSColor(red: 0xE7/255.0, green: 0x8A/255.0, blue: 0x08/255.0, alpha: 1),
      bot: NSColor(red: 0xD9/255.0, green: 0x77/255.0, blue: 0x06/255.0, alpha: 1))
  case .done:
    return GradientColors(
      top: NSColor(red: 0x4A/255.0, green: 0xDE/255.0, blue: 0x80/255.0, alpha: 1),
      mid: NSColor(red: 0x30/255.0, green: 0xC0/255.0, blue: 0x65/255.0, alpha: 1),
      bot: NSColor(red: 0x16/255.0, green: 0xA3/255.0, blue: 0x4A/255.0, alpha: 1))
  case .error:
    return GradientColors(
      top: NSColor(red: 0xFF/255.0, green: 0x7B/255.0, blue: 0x7B/255.0, alpha: 1),
      mid: NSColor(red: 0xF7/255.0, green: 0x5F/255.0, blue: 0x5F/255.0, alpha: 1),
      bot: NSColor(red: 0xEF/255.0, green: 0x44/255.0, blue: 0x44/255.0, alpha: 1))
  case .disabled:
    return isDark
      ? GradientColors(
          top: NSColor(red: 0x52/255.0, green: 0x52/255.0, blue: 0x5B/255.0, alpha: 1),
          mid: NSColor(red: 0x48/255.0, green: 0x48/255.0, blue: 0x50/255.0, alpha: 1),
          bot: NSColor(red: 0x3F/255.0, green: 0x3F/255.0, blue: 0x46/255.0, alpha: 1))
      : GradientColors(
          top: NSColor(red: 0x9C/255.0, green: 0xA3/255.0, blue: 0xAF/255.0, alpha: 1),
          mid: NSColor(red: 0x83/255.0, green: 0x8A/255.0, blue: 0x97/255.0, alpha: 1),
          bot: NSColor(red: 0x6B/255.0, green: 0x72/255.0, blue: 0x80/255.0, alpha: 1))
  }
}

// MARK: - Color interpolation helper

private func lerpColor(_ a: NSColor, _ b: NSColor, _ t: CGFloat) -> NSColor {
  let ac = a.usingColorSpace(.deviceRGB) ?? a
  let bc = b.usingColorSpace(.deviceRGB) ?? b
  return NSColor(
    red:   ac.redComponent   + (bc.redComponent   - ac.redComponent)   * t,
    green: ac.greenComponent + (bc.greenComponent - ac.greenComponent) * t,
    blue:  ac.blueComponent  + (bc.blueComponent  - ac.blueComponent)  * t,
    alpha: ac.alphaComponent + (bc.alphaComponent - ac.alphaComponent) * t)
}

// MARK: - Easing

private func easeOut(_ t: CGFloat) -> CGFloat { 1 - pow(1 - t, 3) }
private func easeInOut(_ t: CGFloat) -> CGFloat {
  t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

// MARK: - FloatingButtonView

/// Custom NSView that draws the floating button circle with premium rendering.
class FloatingButtonView: NSView {
  var visualState: FloatingButtonVisualState = .idle {
    didSet {
      if oldValue != visualState {
        prevState = oldValue
        transitionStart = CACurrentMediaTime()
        startAnimationTimer()
      }
      needsDisplay = true
    }
  }
  var isDark: Bool = true { didSet { needsDisplay = true } }
  var masterOpacity: CGFloat = 1.0 { didSet { needsDisplay = true } }

  var onClicked: (() -> Void)?
  var onSecondaryClicked: (() -> Void)?
  var onDragEnded: ((_ x: CGFloat, _ y: CGFloat) -> Void)?

  // Animation state
  private var prevState: FloatingButtonVisualState = .idle
  private var transitionStart: CFTimeInterval = 0
  private var animTimer: CVDisplayLink?
  private var timerSource: DispatchSourceTimer?
  private var animOrigin: CFTimeInterval = 0

  private var isDragging = false
  private var dragStart: NSPoint = .zero

  private static let transitionDuration: CFTimeInterval = 0.2
  private static let pulseRingDuration: CFTimeInterval = 1.4
  private static let breatheDuration: CFTimeInterval = 1.8
  private static let spinnerDuration: CFTimeInterval = 1.2

  // Shadow margin — extra space around the circle for shadow rendering
  private static let shadowMargin: CGFloat = 14

  deinit {
    stopAnimationTimer()
  }

  // MARK: - Animation Timer

  private func startAnimationTimer() {
    guard timerSource == nil else { return }
    animOrigin = CACurrentMediaTime()
    let source = DispatchSource.makeTimerSource(queue: .main)
    source.schedule(deadline: .now(), repeating: 1.0 / 30.0)
    source.setEventHandler { [weak self] in self?.needsDisplay = true }
    source.resume()
    timerSource = source
  }

  private func stopAnimationTimer() {
    timerSource?.cancel()
    timerSource = nil
  }

  private var needsAnimation: Bool {
    let now = CACurrentMediaTime()
    // Transition animation
    if now - transitionStart < Self.transitionDuration { return true }
    // State-specific continuous animations
    switch visualState {
    case .recording, .transcribing: return true
    default: return false
    }
  }

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.clear(bounds)
    ctx.setShouldAntialias(true)
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    let scale = window?.backingScaleFactor ?? 2.0
    let margin = Self.shadowMargin
    let circleRect = bounds.insetBy(dx: margin, dy: margin)
    let center = CGPoint(x: circleRect.midX, y: circleRect.midY)
    let radius = min(circleRect.width, circleRect.height) / 2

    let now = CACurrentMediaTime()

    // Resolve colors (with transition interpolation)
    let curColors = colorsFor(state: visualState, isDark: isDark)
    let tTransition = min(1, CGFloat((now - transitionStart) / Self.transitionDuration))
    let colors: GradientColors
    if tTransition < 1 {
      let prevColors = colorsFor(state: prevState, isDark: isDark)
      let t = easeOut(tTransition)
      colors = GradientColors(
        top: lerpColor(prevColors.top, curColors.top, t),
        mid: lerpColor(prevColors.mid, curColors.mid, t),
        bot: lerpColor(prevColors.bot, curColors.bot, t))
    } else {
      colors = curColors
    }

    // Body breathe scale (recording only — idle uses hover scale in Dart FAB)
    var bodyScale: CGFloat = 1.0
    if visualState == .recording {
      let tBreathe = CGFloat(now - animOrigin).truncatingRemainder(dividingBy: CGFloat(Self.breatheDuration)) / CGFloat(Self.breatheDuration)
      let breatheT = easeInOut(tBreathe < 0.5 ? tBreathe * 2 : 2 - tBreathe * 2)
      bodyScale = 1.0 + 0.04 * breatheT
    }

    // Pulse ring during recording
    if visualState == .recording {
      drawPulseRing(ctx: ctx, center: center, baseRadius: radius, now: now, colors: colors)
    }

    // Multi-layer soft shadow (12 layers matching Windows)
    drawSoftShadow(ctx: ctx, center: center, radius: radius * bodyScale)

    // Gradient-filled circle
    drawGradientCircle(ctx: ctx, center: center, radius: radius * bodyScale, colors: colors, scale: scale)

    // Subtle border
    let borderColor = isDark
      ? NSColor.white.withAlphaComponent(0.12 * masterOpacity)
      : NSColor.black.withAlphaComponent(0.08 * masterOpacity)
    ctx.setStrokeColor(borderColor.cgColor)
    ctx.setLineWidth(1.0 / scale)
    let borderRect = NSRect(
      x: center.x - radius * bodyScale, y: center.y - radius * bodyScale,
      width: radius * bodyScale * 2, height: radius * bodyScale * 2)
    ctx.strokeEllipse(in: borderRect)

    // Draw centered icon
    drawIcon(ctx: ctx, center: center, radius: radius * bodyScale, now: now)

    // Stop timer if no animation needed
    if !needsAnimation { stopAnimationTimer() }
  }

  // MARK: - Soft Shadow

  private func drawSoftShadow(ctx: CGContext, center: CGPoint, radius: CGFloat) {
    let layers = 12
    for i in 0..<layers {
      let t = CGFloat(i + 1) / CGFloat(layers)
      let blur = 2 + 12 * t
      let expand = blur * 0.5
      let alpha = 0.03 * (1 - t * 0.6) * masterOpacity
      let yOffset: CGFloat = 3 * t

      ctx.saveGState()
      ctx.setShadow(offset: CGSize(width: 0, height: -yOffset), blur: blur,
                     color: NSColor.black.withAlphaComponent(alpha).cgColor)
      ctx.setFillColor(NSColor.black.withAlphaComponent(0.001).cgColor)
      let r = NSRect(
        x: center.x - radius - expand, y: center.y - radius - expand,
        width: (radius + expand) * 2, height: (radius + expand) * 2)
      ctx.fillEllipse(in: r)
      ctx.restoreGState()
    }
  }

  // MARK: - Gradient Circle

  private func drawGradientCircle(ctx: CGContext, center: CGPoint, radius: CGFloat,
                                   colors: GradientColors, scale: CGFloat) {
    ctx.saveGState()

    // Clip to circle
    let circleRect = NSRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)
    ctx.addEllipse(in: circleRect)
    ctx.clip()

    // 3-stop linear gradient (top-left to bottom-right, matching Dart FAB)
    let cgColors = [
      colors.top.withAlphaComponent(masterOpacity).cgColor,
      colors.mid.withAlphaComponent(masterOpacity).cgColor,
      colors.bot.withAlphaComponent(masterOpacity).cgColor,
    ] as CFArray
    let locations: [CGFloat] = [0, 0.5, 1]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: cgColors, locations: locations) {
      let startPoint = CGPoint(x: center.x - radius, y: center.y + radius)
      let endPoint = CGPoint(x: center.x + radius, y: center.y - radius)
      ctx.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
    }

    ctx.restoreGState()
  }

  // MARK: - Pulse Ring

  private func drawPulseRing(ctx: CGContext, center: CGPoint, baseRadius: CGFloat,
                              now: CFTimeInterval, colors: GradientColors) {
    let elapsed = now - animOrigin
    let t = CGFloat(elapsed.truncatingRemainder(dividingBy: Self.pulseRingDuration) / Self.pulseRingDuration)
    let scale = 1.0 + (1.8 - 1.0) * easeOut(t)
    let alpha = (1.0 - easeOut(t)) * 0.5 * masterOpacity

    let ringRadius = baseRadius * scale
    ctx.setStrokeColor(colors.top.withAlphaComponent(alpha).cgColor)
    ctx.setLineWidth(2.0)
    let ringRect = NSRect(x: center.x - ringRadius, y: center.y - ringRadius,
                          width: ringRadius * 2, height: ringRadius * 2)
    ctx.strokeEllipse(in: ringRect)
  }

  // MARK: - Icon Drawing (Lucide-quality paths in 24×24 space)

  private func drawIcon(ctx: CGContext, center: CGPoint, radius: CGFloat, now: CFTimeInterval) {
    let iconScale = radius * 0.55 / 12.0 // Map 24×24 space to actual size
    let iconColor = NSColor.white.withAlphaComponent(1.0 * masterOpacity)

    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: iconScale, y: iconScale)

    ctx.setStrokeColor(iconColor.cgColor)
    ctx.setFillColor(NSColor.clear.cgColor)
    ctx.setLineWidth(2.0)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    switch visualState {
    case .idle:
      drawMicIcon(ctx: ctx)
    case .recording:
      drawSquareIcon(ctx: ctx)
    case .transcribing:
      drawSpinnerIcon(ctx: ctx, now: now)
    case .done:
      drawCheckIcon(ctx: ctx)
    case .error:
      drawAlertIcon(ctx: ctx)
    case .disabled:
      drawMicIcon(ctx: ctx)
      // Overlay a subtle slash for disabled
      ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.4 * masterOpacity).cgColor)
      ctx.move(to: CGPoint(x: -8, y: -8))
      ctx.addLine(to: CGPoint(x: 8, y: 8))
      ctx.strokePath()
    }

    ctx.restoreGState()
  }

  /// Lucide mic icon: capsule body (8,2→16,12 rx=4) + holder arc + stem + base.
  /// Coordinates mapped to a centred ±12 space matching the 24×24 Lucide viewBox.
  private func drawMicIcon(ctx: CGContext) {
    // Capsule body — Lucide: rect (8,2)→(16,12), rx=4, mapped to centre-origin
    let capsuleRect = CGRect(x: -4, y: -1, width: 8, height: 10)
    let capsulePath = CGPath(roundedRect: capsuleRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
    ctx.addPath(capsulePath)
    ctx.strokePath()

    // Holder arc — Lucide: path from (6,11) curving down to (18,11), radius=6
    ctx.addArc(center: CGPoint(x: 0, y: 1), radius: 6, startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()

    // Stem — vertical line from arc bottom to base
    ctx.move(to: CGPoint(x: 0, y: -5))
    ctx.addLine(to: CGPoint(x: 0, y: -9))
    ctx.strokePath()

    // Base — horizontal line at bottom
    ctx.move(to: CGPoint(x: -3, y: -9))
    ctx.addLine(to: CGPoint(x: 3, y: -9))
    ctx.strokePath()
  }

  /// Lucide square icon (stop): stroke-only rounded rectangle matching Dart LucideIcons.square.
  private func drawSquareIcon(ctx: CGContext) {
    let rect = CGRect(x: -6, y: -6, width: 12, height: 12)
    let path = CGPath(roundedRect: rect, cornerWidth: 2, cornerHeight: 2, transform: nil)
    ctx.addPath(path)
    ctx.strokePath()
  }

  /// Spinner (288° arc, rotating) for transcribing state.
  private func drawSpinnerIcon(ctx: CGContext, now: CFTimeInterval) {
    let elapsed = now - animOrigin
    let angle = CGFloat(elapsed.truncatingRemainder(dividingBy: Self.spinnerDuration) / Self.spinnerDuration) * .pi * 2
    let arcLength: CGFloat = .pi * 1.6 // 288°

    ctx.addArc(center: .zero, radius: 8, startAngle: angle, endAngle: angle + arcLength, clockwise: false)
    ctx.strokePath()
  }

  /// Lucide check icon.
  private func drawCheckIcon(ctx: CGContext) {
    ctx.move(to: CGPoint(x: -6, y: 0))
    ctx.addLine(to: CGPoint(x: -2, y: -5))
    ctx.addLine(to: CGPoint(x: 8, y: 6))
    ctx.strokePath()
  }

  /// Lucide alert-triangle icon.
  private func drawAlertIcon(ctx: CGContext) {
    // Triangle
    ctx.move(to: CGPoint(x: 0, y: 9))
    ctx.addLine(to: CGPoint(x: -9, y: -6))
    ctx.addLine(to: CGPoint(x: 9, y: -6))
    ctx.closePath()
    ctx.strokePath()

    // Exclamation line
    ctx.move(to: CGPoint(x: 0, y: 5))
    ctx.addLine(to: CGPoint(x: 0, y: 0))
    ctx.strokePath()

    // Dot
    ctx.setFillColor(NSColor.white.withAlphaComponent(1.0 * masterOpacity).cgColor)
    ctx.fillEllipse(in: CGRect(x: -1, y: -4, width: 2, height: 2))
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
    if isDragging, let panel = window {
      let origin = panel.frame.origin
      onDragEnded?(origin.x, origin.y)
    } else {
      onClicked?()
    }
    isDragging = false
  }

  override func rightMouseUp(with event: NSEvent) {
    onSecondaryClicked?()
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
