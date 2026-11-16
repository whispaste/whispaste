// Renders the DMG window background (#245): brand header, the drag hint and two
// numbered steps (app plate -> Applications plate) joined by an arrow. The DMG is
// one build for every language, so the hint is German (primary market) with
// English below. Colours come from design-tokens/primitives.tokens.json.
// Geometry must match scripts/release/mac-dmg.sh: content 600x380, icons 96 px
// centred at x 170 / 430, y 230. The image is taller than the content so a
// slightly larger Finder window never shows an uncovered strip.
//
// Usage: swift installer/macos/make-dmg-background.swift
// Writes installer/macos/dmg-background.tiff (1x + 2x in one file).
import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[0])
  .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
for name in ["HankenGrotesk-w500", "HankenGrotesk-w600", "BricolageGrotesque-w600", "BricolageGrotesque-w700"] {
  let font = root.appendingPathComponent("assets/fonts/\(name).ttf")
  CTFontManagerRegisterFontsForURL(font as CFURL, .process, nil)
}
let appIcon = NSImage(contentsOf: root.appendingPathComponent("website/public/app-icon.png"))

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let navy900 = color(0x0B122A)
let navy700 = color(0x13274F)
let navy800 = color(0x122247)
let white = color(0xFFFFFF)
let muted = color(0xA9B6CC)  // light secondary text on navy
let cyan = color(0x6FDDF0)  // cyan.300, action
let amber = color(0xFFB547)  // amber.400, step markers

let width: CGFloat = 600
let height: CGFloat = 440
let iconY: CGFloat = 230
let iconX: [CGFloat] = [170, 430]

func font(_ name: String, _ size: CGFloat) -> NSFont {
  guard let f = NSFont(name: name, size: size) else { fatalError("font \(name) missing") }
  return f
}

func render(scale: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  rep.size = NSSize(width: width, height: height)
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  // Flip so coordinates match Finder's (origin top left).
  let transform = NSAffineTransform()
  transform.translateX(by: 0, yBy: height)
  transform.scaleX(by: 1, yBy: -1)
  transform.concat()

  // Navy band with a soft wash from the top centre (stage navy -> app background).
  navy900.setFill()
  NSRect(x: 0, y: 0, width: width, height: height).fill()
  NSGradient(starting: navy700, ending: navy900)!
    .draw(fromCenter: NSPoint(x: width / 2, y: 40), radius: 0,
          toCenter: NSPoint(x: width / 2, y: 40), radius: 360, options: [])

  func text(_ s: String, _ f: NSFont, _ c: NSColor, x: CGFloat? = nil, top: CGFloat) -> CGFloat {
    let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: c]
    let size = (s as NSString).size(withAttributes: attrs)
    NSGraphicsContext.saveGraphicsState()
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: top + size.height)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    (s as NSString).draw(at: NSPoint(x: x ?? (width - size.width) / 2, y: 0), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return size.width
  }

  // Brand row: app icon + wordmark, centred together.
  let brand = font("BricolageGrotesque-24ptBold", 17)
  let brandWidth = ("WhisPaste" as NSString).size(withAttributes: [.font: brand]).width
  let mark: CGFloat = 24
  let rowX = (width - (mark + 8 + brandWidth)) / 2
  if let appIcon {
    NSGraphicsContext.saveGraphicsState()
    let flip = NSAffineTransform()
    flip.translateX(by: 0, yBy: 28 + mark)
    flip.scaleX(by: 1, yBy: -1)
    flip.concat()
    appIcon.draw(in: NSRect(x: rowX, y: 0, width: mark, height: mark))
    NSGraphicsContext.restoreGraphicsState()
  }
  _ = text("WhisPaste", brand, white, x: rowX + mark + 8, top: 29)

  _ = text("In Programme ziehen", font("BricolageGrotesque-24ptSemiBold", 28), white, top: 70)
  _ = text("Drag WhisPaste to Applications", font("HankenGrotesk-Medium", 14), muted, top: 110)

  // Step plates, one step lighter than the band, each with an amber number.
  for (i, x) in iconX.enumerated() {
    let plate = NSRect(x: x - 78, y: iconY - 72, width: 156, height: 152)
    let path = NSBezierPath(roundedRect: plate, xRadius: 20, yRadius: 20)
    navy800.setFill()
    path.fill()
    color(0xFFFFFF, 0.10).setStroke()
    path.lineWidth = 1
    path.stroke()
    // Finder draws icon labels in dark text even on a dark background, so each label
    // sits on a light pill (glacier.50).
    color(0xF3F7FB).setFill()
    NSBezierPath(roundedRect: NSRect(x: x - 64, y: iconY + 53, width: 128, height: 24),
                 xRadius: 12, yRadius: 12).fill()
    let badge = NSRect(x: plate.minX + 12, y: plate.minY + 12, width: 22, height: 22)
    amber.setFill()
    NSBezierPath(ovalIn: badge).fill()
    let numFont = font("HankenGrotesk-SemiBold", 13)
    let num = "\(i + 1)"
    let numWidth = (num as NSString).size(withAttributes: [.font: numFont]).width
    _ = text(num, numFont, navy900, x: badge.midX - numWidth / 2, top: badge.minY + 3)
  }

  // Arrow between the plates.
  let start = iconX[0] + 92
  let end = iconX[1] - 92
  cyan.setStroke()
  let shaft = NSBezierPath()
  shaft.lineWidth = 4
  shaft.lineCapStyle = .round
  shaft.move(to: NSPoint(x: start, y: iconY))
  shaft.line(to: NSPoint(x: end - 8, y: iconY))
  shaft.stroke()
  cyan.setFill()
  let head = NSBezierPath()
  head.move(to: NSPoint(x: end + 2, y: iconY))
  head.line(to: NSPoint(x: end - 14, y: iconY - 11))
  head.line(to: NSPoint(x: end - 14, y: iconY + 11))
  head.close()
  head.fill()

  _ = text(
    "Danach WhisPaste in Programme öffnen  ·  Then open it from Applications",
    font("HankenGrotesk-Medium", 12), muted, top: 336)

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let image = NSImage(size: NSSize(width: width, height: height))
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
let out = root.appendingPathComponent("installer/macos/dmg-background.tiff")
guard let data = image.tiffRepresentation(using: .lzw, factor: 0) else { fatalError("tiff") }
try data.write(to: out)
print("wrote \(out.path)")
