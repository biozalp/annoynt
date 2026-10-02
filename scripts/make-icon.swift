// Renders the Annoynt app icon: a desktop sliding in fast, with speed lines. Output: Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift
import AppKit

func render(size px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 1024, height: 1024)   // draw in a 1024-pt canvas
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824-pt rounded square centred in 1024, with a soft shadow.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor.black.setFill()
    squircle.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [NSColor(red: 0.36, green: 0.27, blue: 0.95, alpha: 1),
                        NSColor(red: 0.13, green: 0.60, blue: 0.98, alpha: 1)])!
        .draw(in: squircle, angle: -60)

    // Two "desktops": the outgoing one dimmed on the left, the incoming one bright.
    func desktop(_ rect: NSRect, alpha: CGFloat) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 44, yRadius: 44)
        NSColor.white.withAlphaComponent(alpha).setFill()
        path.fill()
        // menu bar strip
        let bar = NSBezierPath(roundedRect: NSRect(x: rect.minX + 28, y: rect.maxY - 64,
                                                   width: rect.width - 56, height: 22),
                               xRadius: 11, yRadius: 11)
        NSColor(red: 0.30, green: 0.35, blue: 0.95, alpha: alpha * 0.35).setFill()
        bar.fill()
    }
    desktop(NSRect(x: 410, y: 347, width: 450, height: 330), alpha: 1.0)

    // Speed lines trailing the incoming desktop, fading out behind it.
    for (y, length, alpha) in [(430.0, 150.0, 0.55), (512.0, 220.0, 0.9), (594.0, 120.0, 0.55)] {
        let line = NSBezierPath()
        line.lineWidth = 30
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: 360 - length, y: y))
        line.line(to: NSPoint(x: 360, y: y))
        NSColor.white.withAlphaComponent(alpha).setStroke()
        line.stroke()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        let png = render(size: base * scale).representation(using: .png, properties: [:])!
        try! png.write(to: iconset.appendingPathComponent(name))
    }
}

let out = "Resources/AppIcon.icns"
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out]
try! task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(out)")
