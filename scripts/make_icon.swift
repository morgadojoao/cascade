// Renders the Cascade app icon (three cascaded windows on a blue tile)
// and writes assets/Cascade.icns. Run from the repo root:
//   swift scripts/make_icon.swift
import AppKit

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024.0

    // Background tile (macOS icon grid: 824pt tile inside 1024 canvas)
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.56, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.10, green: 0.27, blue: 0.78, alpha: 1))!
        .draw(in: tilePath, angle: -90)

    // Three windows, back to front, stepping down-right
    let w: CGFloat = 470 * s, h: CGFloat = 340 * s, step: CGFloat = 105 * s
    let dots = [NSColor.systemRed, NSColor.systemYellow, NSColor.systemGreen]
    for i in 0..<3 {
        let x = 172 * s + CGFloat(i) * step
        let y = 924 * s - 137 * s - h - CGFloat(i) * step
        let r = NSRect(x: x, y: y, width: w, height: h)
        let path = NSBezierPath(roundedRect: r, xRadius: 30 * s, yRadius: 30 * s)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
        shadow.shadowBlurRadius = 24 * s
        shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
        shadow.set()
        NSColor(white: 1.0 - CGFloat(2 - i) * 0.07, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Title bar
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor(white: 0.86 - CGFloat(2 - i) * 0.05, alpha: 1).setFill()
        NSRect(x: x, y: y + h - 62 * s, width: w, height: 62 * s).fill()
        NSGraphicsContext.restoreGraphicsState()

        for (d, c) in dots.enumerated() {
            c.setFill()
            NSBezierPath(ovalIn: NSRect(x: x + (28 + CGFloat(d) * 40) * s,
                                        y: y + h - 44 * s,
                                        width: 26 * s, height: 26 * s)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Cascade.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let data = render(base * scale).representation(using: .png, properties: [:])!
        try! data.write(to: iconset.appendingPathComponent(name))
    }
}
try? fm.createDirectory(atPath: "assets", withIntermediateDirectories: true)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", "assets/Cascade.icns"]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "Wrote assets/Cascade.icns" : "iconutil failed")
