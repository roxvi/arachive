import AppKit
import ImageIO

_ = NSApplication.shared

// iOS applies its own corner mask. Keep the same white A and green as the Mac app.
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 5 / 255, green: 150 / 255, blue: 105 / 255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
let letter = NSAttributedString(string: "A", attributes: [
    .font: NSFont.systemFont(ofSize: 512, weight: .semibold), .foregroundColor: NSColor.white
])
let size = letter.size()
letter.draw(at: NSPoint(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2))
NSGraphicsContext.restoreGraphicsState()
let opaque = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
    bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(bitmap.cgImage!, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, opaque.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
