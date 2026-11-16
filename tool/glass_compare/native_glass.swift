// Comparison window for the glass look: the real macOS 26+ glass capsule
// (NSGlassEffectView) on the same three backgrounds the gallery's replica uses.
// Run with `swift tool/glass_compare/native_glass.swift`. Dev tool only; it is
// not part of the app.

import Cocoa

let folder = (#filePath as NSString).deletingLastPathComponent
let backgrounds = ["bg_light.png", "bg_wallpaper.png", "bg_pattern.png"]
// Ink (dark) on the light background, white on the two dark ones.
let contentColours: [NSColor] = [
    NSColor(red: 11 / 255, green: 18 / 255, blue: 42 / 255, alpha: 1),
    .white,
    .white,
]

let bgWidth: CGFloat = 420
let bgHeight: CGFloat = 160
let pillWidth: CGFloat = 330
let pillHeight: CGFloat = 64

/// Monochrome placeholder content: x mark, timer, wave bars, stop square.
final class PlaceholderContent: NSView {
    let colour: NSColor

    init(frame: NSRect, colour: NSColor) {
        self.colour = colour
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        colour.setFill()
        colour.setStroke()
        let cy = bounds.height / 2

        let cross = NSBezierPath()
        cross.lineWidth = 2.5
        cross.lineCapStyle = .round
        cross.move(to: NSPoint(x: 29, y: cy - 6))
        cross.line(to: NSPoint(x: 41, y: cy + 6))
        cross.move(to: NSPoint(x: 29, y: cy + 6))
        cross.line(to: NSPoint(x: 41, y: cy - 6))
        cross.stroke()

        let font = NSFont.monospacedDigitSystemFont(ofSize: 16, weight: .medium)
        ("0:07" as NSString).draw(
            at: NSPoint(x: 60, y: cy - 10),
            withAttributes: [.font: font, .foregroundColor: colour]
        )

        let bars: [CGFloat] = [6, 12, 18, 10, 22, 14, 8, 16, 20, 10, 6]
        for (i, h) in bars.enumerated() {
            let x = 140 + CGFloat(i) * 7
            NSBezierPath(
                roundedRect: NSRect(x: x, y: cy - h / 2, width: 3.5, height: h),
                xRadius: 1.75, yRadius: 1.75
            ).fill()
        }

        NSBezierPath(
            roundedRect: NSRect(x: bounds.width - 46, y: cy - 8, width: 16, height: 16),
            xRadius: 3, yRadius: 3
        ).fill()
    }
}

/// The capsule: NSGlassEffectView on macOS 26+, a hud vibrancy pill before.
func glassCapsule(frame: NSRect, colour: NSColor, clear: Bool) -> NSView {
    let content = PlaceholderContent(frame: NSRect(origin: .zero, size: frame.size), colour: colour)
    if #available(macOS 26.0, *) {
        let glass = NSGlassEffectView(frame: frame)
        glass.cornerRadius = frame.height / 2
        glass.style = clear ? .clear : .regular
        glass.contentView = content
        return glass
    }
    let vibrancy = NSVisualEffectView(frame: frame)
    vibrancy.material = .hudWindow
    vibrancy.blendingMode = .behindWindow
    vibrancy.state = .active
    vibrancy.wantsLayer = true
    vibrancy.layer?.cornerRadius = frame.height / 2
    vibrancy.layer?.masksToBounds = true
    vibrancy.addSubview(content)
    return vibrancy
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two columns: left .regular, right .clear (the clear iOS glass).
        let columns = 2
        let rowCount = CGFloat(backgrounds.count)
        let size = NSSize(width: bgWidth * CGFloat(columns), height: bgHeight * rowCount)
        let content = NSView(frame: NSRect(origin: .zero, size: size))

        for (row, name) in backgrounds.enumerated() {
            // Row 0 is the top of the window; AppKit rows grow upwards.
            let y = size.height - CGFloat(row + 1) * bgHeight
            for column in 0..<columns {
                let x = CGFloat(column) * bgWidth
                let rowFrame = NSRect(x: x, y: y, width: bgWidth, height: bgHeight)

                let image = NSImageView(frame: rowFrame)
                image.image = NSImage(contentsOfFile: "\(folder)/\(name)")
                image.imageScaling = .scaleAxesIndependently
                content.addSubview(image)

                let pillFrame = NSRect(
                    x: x + (bgWidth - pillWidth) / 2,
                    y: y + (bgHeight - pillHeight) / 2,
                    width: pillWidth,
                    height: pillHeight
                )
                content.addSubview(
                    glassCapsule(frame: pillFrame, colour: contentColours[row], clear: column == 1)
                )
            }
        }

        let win = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Original (macOS-Glas)"
        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        window = win
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.activate(ignoringOtherApps: true)
app.run()
