import AppKit

// Finder uses the point size of this multi-resolution TIFF on Retina displays.
let canvas = NSSize(width: 640, height: 440)
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let image = NSImage(size: canvas)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func centered(_ text: String, top: CGFloat, font: NSFont, ink: NSColor,
              tracking: CGFloat = 0) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: ink, .kern: tracking,
    ]
    let size = (text as NSString).size(withAttributes: attributes)
    (text as NSString).draw(
        at: NSPoint(x: (canvas.width - size.width) / 2,
                    y: canvas.height - top - size.height),
        withAttributes: attributes
    )
}

for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 640 * scale, pixelsHigh: 440 * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.size = canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    color(0x20211f).setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()

    centered("REFS FOR MAC", top: 38, font: .systemFont(ofSize: 11, weight: .semibold),
             ink: color(0xaeb5a4), tracking: 2.2)
    centered("Good ideas. Kept close.", top: 69,
             font: .systemFont(ofSize: 31, weight: .semibold), ink: color(0xffdf20),
             tracking: -1.1)

    color(0xffffff, alpha: 0.08).setStroke()
    let rule = NSBezierPath()
    rule.move(to: NSPoint(x: 56, y: 302))
    rule.line(to: NSPoint(x: 584, y: 302))
    rule.lineWidth = 1
    rule.stroke()

    // Finder draws black filename labels over custom backgrounds.
    color(0xeff0e5).setFill()
    for (center, width): (CGFloat, CGFloat) in [(166, 78), (474, 132)] {
        NSBezierPath(roundedRect: NSRect(x: center - width / 2, y: 123,
                                        width: width, height: 28),
                     xRadius: 14, yRadius: 14).fill()
    }

    // The actual app and Applications icons are supplied by Finder.
    color(0xffdf20).setStroke()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 285, y: 208))
    arrow.line(to: NSPoint(x: 355, y: 208))
    arrow.move(to: NSPoint(x: 345, y: 218))
    arrow.line(to: NSPoint(x: 355, y: 208))
    arrow.line(to: NSPoint(x: 345, y: 198))
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.stroke()

    centered("Drag Refs to Applications to install.", top: 344,
             font: .systemFont(ofSize: 15, weight: .medium), ink: color(0xf0f1e8))
    centered("Save the UI you love. Remember why.", top: 378,
             font: .systemFont(ofSize: 12), ink: color(0x929d85))

    NSGraphicsContext.restoreGraphicsState()
    image.addRepresentation(bitmap)
}

try image.tiffRepresentation!.write(to: output)
