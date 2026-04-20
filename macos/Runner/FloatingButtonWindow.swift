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
    hasShadow = true
    isMovableByWindowBackground = false
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

/// Visual state matching the Dart enum.
enum FloatingButtonVisualState: String {
  case idle, recording, transcribing, done, error, disabled
}

/// Custom NSView that draws the floating button circle.
class FloatingButtonView: NSView {
  var visualState: FloatingButtonVisualState = .idle { didSet { needsDisplay = true } }
  var isDark: Bool = true { didSet { needsDisplay = true } }
  var masterOpacity: CGFloat = 1.0 { didSet { needsDisplay = true } }

  var onClicked: (() -> Void)?
  var onSecondaryClicked: (() -> Void)?
  var onDragEnded: ((_ x: CGFloat, _ y: CGFloat) -> Void)?

  private var isDragging = false
  private var dragStart: NSPoint = .zero

  // MARK: - Drawing

  override func draw(_ dirtyRect: NSRect) {
    guard let ctx = NSGraphicsContext.current?.cgContext else { return }
    ctx.clear(bounds)

    let inset: CGFloat = 2
    let circleRect = bounds.insetBy(dx: inset, dy: inset)

    // Fill color based on state.
    let fillColor = stateColor()
    ctx.setFillColor(fillColor.withAlphaComponent(masterOpacity).cgColor)
    ctx.fillEllipse(in: circleRect)

    // Subtle border.
    let borderColor = isDark
      ? NSColor.white.withAlphaComponent(0.15 * masterOpacity)
      : NSColor.black.withAlphaComponent(0.1 * masterOpacity)
    ctx.setStrokeColor(borderColor.cgColor)
    ctx.setLineWidth(1.5)
    ctx.strokeEllipse(in: circleRect)

    // Draw centered icon.
    drawIcon(in: circleRect, context: ctx)
  }

  private func stateColor() -> NSColor {
    switch visualState {
    case .idle:
      return isDark
        ? NSColor(red: 0.35, green: 0.35, blue: 0.40, alpha: 1)
        : NSColor(red: 0.85, green: 0.85, blue: 0.88, alpha: 1)
    case .recording:
      return NSColor(red: 0.90, green: 0.20, blue: 0.20, alpha: 1)
    case .transcribing:
      return NSColor(red: 0.95, green: 0.70, blue: 0.15, alpha: 1)
    case .done:
      return NSColor(red: 0.20, green: 0.78, blue: 0.35, alpha: 1)
    case .error:
      return NSColor(red: 0.70, green: 0.15, blue: 0.15, alpha: 1)
    case .disabled:
      return isDark
        ? NSColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1)
        : NSColor(red: 0.75, green: 0.75, blue: 0.78, alpha: 1)
    }
  }

  private func drawIcon(in rect: NSRect, context ctx: CGContext) {
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let iconSize = min(rect.width, rect.height) * 0.35

    let iconColor = NSColor.white.withAlphaComponent(0.9 * masterOpacity)
    ctx.setStrokeColor(iconColor.cgColor)
    ctx.setLineWidth(2.0)
    ctx.setLineCap(.round)

    switch visualState {
    case .idle, .recording:
      // Microphone icon (simple path).
      let micW = iconSize * 0.35
      let micH = iconSize * 0.55
      let micRect = NSRect(
        x: center.x - micW, y: center.y - micH * 0.3,
        width: micW * 2, height: micH
      )
      ctx.strokeEllipse(in: micRect)
      // Stem.
      ctx.move(to: NSPoint(x: center.x, y: center.y - micH * 0.3))
      ctx.addLine(to: NSPoint(x: center.x, y: center.y - micH * 0.7))
      ctx.strokePath()

    case .transcribing:
      // Three dots (processing indicator).
      let dotR: CGFloat = 2.5
      let spacing: CGFloat = iconSize * 0.35
      for i in -1...1 {
        let x = center.x + CGFloat(i) * spacing
        ctx.setFillColor(iconColor.cgColor)
        ctx.fillEllipse(in: NSRect(x: x - dotR, y: center.y - dotR, width: dotR * 2, height: dotR * 2))
      }

    case .done:
      // Checkmark.
      let s = iconSize * 0.4
      ctx.move(to: NSPoint(x: center.x - s, y: center.y))
      ctx.addLine(to: NSPoint(x: center.x - s * 0.2, y: center.y - s * 0.7))
      ctx.addLine(to: NSPoint(x: center.x + s, y: center.y + s * 0.6))
      ctx.strokePath()

    case .error:
      // X mark.
      let s = iconSize * 0.3
      ctx.move(to: NSPoint(x: center.x - s, y: center.y - s))
      ctx.addLine(to: NSPoint(x: center.x + s, y: center.y + s))
      ctx.move(to: NSPoint(x: center.x + s, y: center.y - s))
      ctx.addLine(to: NSPoint(x: center.x - s, y: center.y + s))
      ctx.strokePath()

    case .disabled:
      // Dash.
      let s = iconSize * 0.3
      ctx.move(to: NSPoint(x: center.x - s, y: center.y))
      ctx.addLine(to: NSPoint(x: center.x + s, y: center.y))
      ctx.strokePath()
    }
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

  // Accept first mouse so clicks work without activation.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
