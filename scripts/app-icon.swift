import AppKit

// Render the existing assets/icon.svg artwork as a native macOS icon set.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels,
            pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 64, y: CGFloat(pixels) / 64)
        NSColor(calibratedRed: 5 / 255, green: 150 / 255, blue: 105 / 255, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                     xRadius: 14, yRadius: 14).fill()
        let text = NSAttributedString(string: "A", attributes: [
            .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let bounds = text.size()
        text.draw(at: NSPoint(x: (64 - bounds.width) / 2, y: (64 - bounds.height) / 2))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
