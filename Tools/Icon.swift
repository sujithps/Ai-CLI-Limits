import AppKit

// Draws the app icon and writes Resources/AppIcon.icns. Run via ./icon.sh.
//
// Two gauge rings on a dark squircle: the outer one Claude Code, the inner one
// Codex, each partly filled the way the menu bar meters are.

func squircle(in rect: NSRect) -> NSBezierPath {
    // macOS icons use a rounded rect with a radius near 22.4% of the side.
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.224, yRadius: rect.width * 0.224)
}

func ring(center: NSPoint, radius: CGFloat, width: CGFloat, from: CGFloat, to: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    // Clockwise from twelve o'clock, like a clock face.
    path.appendArc(withCenter: center, radius: radius, startAngle: 90 - from, endAngle: 90 - to, clockwise: true)
    return path
}

func drawIcon(side: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: side, height: side))
    image.lockFocus()

    // Apple leaves a margin around the squircle inside the 1024 canvas.
    let inset = side * 0.1
    let tile = NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let shape = squircle(in: tile)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = side * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -side * 0.008)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.13, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.28, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1),
    ])!.draw(in: tile, angle: -90)

    let center = NSPoint(x: tile.midX, y: tile.midY)
    let width = tile.width * 0.085
    let track = NSColor.white.withAlphaComponent(0.14)

    let outerR = tile.width * 0.33
    let innerR = tile.width * 0.20

    track.setStroke()
    ring(center: center, radius: outerR, width: width, from: 0, to: 359.9).stroke()
    ring(center: center, radius: innerR, width: width, from: 0, to: 359.9).stroke()

    // Claude Code, the outer ring, in the orange the menu bar uses at 80%.
    NSColor(calibratedRed: 0.97, green: 0.58, blue: 0.20, alpha: 1).setStroke()
    ring(center: center, radius: outerR, width: width, from: 0, to: 235).stroke()

    // Codex, the inner ring, in a cool accent so the two read as different tools.
    NSColor(calibratedRed: 0.36, green: 0.78, blue: 0.96, alpha: 1).setStroke()
    ring(center: center, radius: innerR, width: width, from: 0, to: 130).stroke()

    // A centre dot anchors the gauges.
    NSColor.white.withAlphaComponent(0.9).setFill()
    let dot = tile.width * 0.05
    NSBezierPath(ovalIn: NSRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)).fill()

    NSGraphicsContext.restoreGraphicsState()
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, pixels: Int, to path: String) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources"
let iconset = "\(out)/AppIcon.iconset"
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
let master = drawIcon(side: 1024)
for size in [16, 32, 128, 256, 512] {
    try writePNG(master, pixels: size, to: "\(iconset)/icon_\(size)x\(size).png")
    try writePNG(master, pixels: size * 2, to: "\(iconset)/icon_\(size)x\(size)@2x.png")
}
try writePNG(master, pixels: 512, to: "\(out)/../docs/icon.png")
print("wrote \(iconset)")
