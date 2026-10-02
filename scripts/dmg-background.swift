// Renders the Annoynt DMG install-window background. Output:
// dmg-assets/background.png (1200×800 px @ 144 dpi = 600×400 points, crisp on Retina).
//
//   swift scripts/dmg-background.swift
import AppKit

let W = 600.0, H = 400.0, scale = 2.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

NSColor(white: 0.97, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()

/// Draws `s` horizontally centred with its top at `topY` points from the top edge.
func drawCentered(_ s: String, _ attrs: [NSAttributedString.Key: Any], topY: Double) {
    let size = s.size(withAttributes: attrs)
    s.draw(at: NSPoint(x: (W - size.width) / 2, y: H - topY - size.height), withAttributes: attrs)
}

drawCentered("Annoynt", [
    .font: NSFont.systemFont(ofSize: 30, weight: .bold),
    .foregroundColor: NSColor(red: 0.25, green: 0.30, blue: 0.90, alpha: 1),
], topY: 40)

drawCentered("Drag Annoynt onto the Applications folder to install", [
    .font: NSFont.systemFont(ofSize: 13, weight: .regular),
    .foregroundColor: NSColor(white: 0.45, alpha: 1),
], topY: 84)

// Arrow from the app icon toward the Applications drop target (icons sit at y≈215).
let y = H - 215
NSColor(white: 0.55, alpha: 1).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 2
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 245, y: y))
arrow.line(to: NSPoint(x: 357, y: y))
arrow.move(to: NSPoint(x: 345, y: y + 8))
arrow.line(to: NSPoint(x: 358, y: y))
arrow.line(to: NSPoint(x: 345, y: y - 8))
arrow.stroke()

drawCentered("After launching, allow Annoynt in System Settings › Privacy & Security › Accessibility", [
    .font: NSFont.systemFont(ofSize: 11, weight: .regular),
    .foregroundColor: NSColor(white: 0.5, alpha: 1),
], topY: 340)

NSGraphicsContext.restoreGraphicsState()

try? FileManager.default.createDirectory(atPath: "dmg-assets", withIntermediateDirectories: true)
let url = URL(fileURLWithPath: "dmg-assets/background.png")
try! rep.representation(using: .png, properties: [:])!.write(to: url)
print("Wrote \(url.path)")
