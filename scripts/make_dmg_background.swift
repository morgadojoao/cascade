// Renders the DMG window background: a light gradient, an arrow from the app
// icon position to the Applications position, and a caption. Writes
// assets/dmg_background.png (600x400) and assets/dmg_background@2x.png.
// Run from the repo root:   swift scripts/make_dmg_background.swift
//
// Icon centres must match make_installer.command: app (150, 190), Applications
// (450, 190), in Finder coordinates (origin top-left, points).
import AppKit

let width: CGFloat = 600, height: CGFloat = 400

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height) // 72 dpi at 1x, 144 dpi at 2x
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Background
    NSGradient(starting: NSColor(calibratedWhite: 0.98, alpha: 1),
               ending: NSColor(calibratedRed: 0.88, green: 0.92, blue: 0.98, alpha: 1))!
        .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -90)

    // Arrow between the icons (AppKit y is flipped: Finder y 190 -> 400 - 190)
    let y = height - 190
    let blue = NSColor(calibratedRed: 0.17, green: 0.42, blue: 0.90, alpha: 1)
    blue.setStroke()
    blue.setFill()
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 240, y: y))
    shaft.line(to: NSPoint(x: 340, y: y))
    shaft.lineWidth = 8
    shaft.lineCapStyle = .round
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 362, y: y))
    head.line(to: NSPoint(x: 335, y: y + 20))
    head.line(to: NSPoint(x: 335, y: y - 20))
    head.close()
    head.fill()

    // Caption
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 17, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.25, alpha: 1),
        .paragraphStyle: style,
    ]
    ("Drag Cascade to Applications to install" as NSString)
        .draw(in: NSRect(x: 0, y: 70, width: width, height: 26), withAttributes: attrs)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
try! render(scale: 1).write(to: URL(fileURLWithPath: "assets/dmg_background.png"))
try! render(scale: 2).write(to: URL(fileURLWithPath: "assets/dmg_background@2x.png"))
print("Wrote assets/dmg_background.png and assets/dmg_background@2x.png")
