// Renders the omninote app icon: a dark rounded square, an indigo ring, and three note lines.
// usage: swift scripts/make-icon.swift <out-dir>   (writes icon_*.png files for iconutil)
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func draw(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    let s = size
    let inset = s * 0.05  // macOS icons leave a margin around the rounded square
    let square = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: square, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: NSColor(srgbRed: 0.11, green: 0.12, blue: 0.17, alpha: 1),
               ending: NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1))!.draw(in: bg, angle: -90)

    // Ring: the "o" of omninote.
    let ringRect = square.insetBy(dx: s * 0.2, dy: s * 0.2)
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = s * 0.075
    NSColor(srgbRed: 0.49, green: 0.55, blue: 0.97, alpha: 1).setStroke()
    ring.stroke()

    // Three note lines inside the ring, the last one short like a trailing thought.
    NSColor(srgbRed: 0.9, green: 0.9, blue: 0.92, alpha: 1).setFill()
    let lineH = s * 0.045
    let widths: [CGFloat] = [0.3, 0.3, 0.17]
    for (i, w) in widths.enumerated() {
        let y = ringRect.midY + s * 0.11 - CGFloat(i) * s * 0.11 - lineH / 2
        let r = NSRect(x: ringRect.midX - s * 0.15, y: y, width: s * w, height: lineH)
        NSBezierPath(roundedRect: r, xRadius: lineH / 2, yRadius: lineH / 2).fill()
    }
    img.unlockFocus()
    return img
}

for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
                   ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
                   ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let img = draw(size: CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}
print("wrote icons to \(outDir)")
