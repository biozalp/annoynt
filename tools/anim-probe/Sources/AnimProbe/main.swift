// Experiment harness: records the screen at 120 fps while a space switch runs,
// then reports animation duration and flicker metrics.
//
// usage: AnimProbe <recipe> [params...]   (run from tools/anim-probe; needs
// Accessibility + Screen Recording for the terminal; quit Annoynt first except
// for key/key2/phys, which go through the running app)
//   key                      native Ctrl+Arrow (synthetic key events)
//   key2                     two Ctrl+Arrow presses 60 ms apart
//   phys                     unmarked swipe shaped like a trackpad gesture
//   timed <seconds>          v0.1 hand-driven progress stream (flickers; kept for comparison)
//   vel <velocity> <travel>  augmented B/C/E, |progress|=travel each, Ended velocity
//   velnoenv <v> <travel>    same without companion gesture envelopes

import AppKit
import CoreGraphics
import CoreMedia
import ScreenCaptureKit

let W = 360, H = 234

struct Frame { let t: Double; let gray: [UInt8] }

final class Recorder: NSObject, SCStreamOutput {
    var frames: [Frame] = []
    let lock = NSLock()
    let t0 = CACurrentMediaTime()
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let px = CMSampleBufferGetImageBuffer(sb) else { return }
        CVPixelBufferLockBaseAddress(px, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(px, .readOnly) }
        let base = CVPixelBufferGetBaseAddress(px)!.assumingMemoryBound(to: UInt8.self)
        let bpr = CVPixelBufferGetBytesPerRow(px)
        let w = min(W, CVPixelBufferGetWidth(px)), h = min(H, CVPixelBufferGetHeight(px))
        var g = [UInt8](repeating: 0, count: W * H)
        for y in 0..<h { for x in 0..<w {
            let p = base + y * bpr + x * 4
            g[y * W + x] = UInt8((Int(p[2]) * 30 + Int(p[1]) * 59 + Int(p[0]) * 11) / 100)
        } }
        let t = CACurrentMediaTime() - t0
        lock.lock(); frames.append(Frame(t: t, gray: g)); lock.unlock()
    }
}

func diff(_ a: [UInt8], _ b: [UInt8]) -> Double {
    var s = 0; for i in 0..<a.count { s += abs(Int(a[i]) - Int(b[i])) }; return Double(s) / Double(a.count)
}
func lum(_ a: [UInt8]) -> Double { Double(a.reduce(0) { $0 + Int($1) }) / Double(a.count) }

/// Horizontal shift (in px of the W-wide frame) that best aligns `f` to `ref`
/// using column-mean profiles — approximates slide position.
func shift(_ f: [UInt8], _ ref: [UInt8]) -> Int {
    func prof(_ a: [UInt8]) -> [Double] { (0..<W).map { x in var s = 0; for y in stride(from: 0, to: H, by: 2) { s += Int(a[y*W+x]) }; return Double(s) } }
    let pf = prof(f), pr = prof(ref)
    var best = 0, bestErr = Double.infinity
    for s in -W+20..<W-20 {
        var e = 0.0, n = 0
        for x in 0..<W { let xr = x + s; if xr >= 0 && xr < W { e += abs(pf[x] - pr[xr]); n += 1 } }
        if n > 20 { e /= Double(n); if e < bestErr { bestErr = e; best = s } }
    }
    return best
}

func savePNG(_ frames: [Frame], to path: String) {
    let cols = 6, rows = (frames.count + cols - 1) / cols
    guard rows > 0, let ctx = CGContext(data: nil, width: cols * W, height: rows * H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
    for (i, f) in frames.enumerated() {
        var g = f.gray
        let img = g.withUnsafeMutableBytes { buf -> CGImage? in
            CGContext(data: buf.baseAddress, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
        let col = i % cols, row = i / cols
        if let img { ctx.draw(img, in: CGRect(x: col * W, y: (rows - 1 - row) * H, width: W, height: H)) }
    }
    guard let out = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, out, nil); CGImageDestinationFinalize(dest)
}

// MARK: - Recipes

func postKey(_ right: Bool) {
    let code: CGKeyCode = right ? 124 : 123
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
        e.flags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
        e.post(tap: .cghidEventTap)
    }
}

func postVel(_ dir: Int, velocity: Double, travel: Double, envelopes: Bool) {
    let s = DockSwipe.sign(for: dir, userReversed: false)
    for phase in [GesturePhase.began, .changed, .ended] {
        let e = DockSwipe.makeEvent(phase: phase, progress: s * travel, velocity: phase == .ended ? s * velocity : nil)!
        e.post(tap: .cgSessionEventTap)
        if envelopes { DockSwipe.makeEnvelope()!.post(tap: .cgSessionEventTap) }
    }
}

func postTimed(_ dir: Int, duration: Double) {
    let s = DockSwipe.sign(for: dir, userReversed: false)
    DockSwipe.makeEvent(phase: .began, progress: s * (1.0/65536))!.post(tap: .cgSessionEventTap)
    let start = CACurrentMediaTime()
    while true {
        let t = (CACurrentMediaTime() - start) / duration
        if t >= 1 { break }
        let p = max(1 - pow(1 - t, 3), (1.0/65536))
        DockSwipe.makeEvent(phase: .changed, progress: s * p)!.post(tap: .cgSessionEventTap)
        usleep(8333)
    }
    DockSwipe.makeEvent(phase: .changed, progress: s)!.post(tap: .cgSessionEventTap)
    DockSwipe.makeEvent(phase: .ended, progress: s, velocity: s * DockSwipe.commitVelocity)!.post(tap: .cgSessionEventTap)
}

/// Physical-looking swipe: unmarked, progress ramps in physical sign (+ = right).
func postPhys(_ dir: Int) {
    let s = Double(dir)
    func post(_ phase: GesturePhase, _ p: Double, _ v: Double? = nil) {
        DockSwipe.makeEvent(phase: phase, progress: s * p, velocity: v.map { s * $0 })!.post(tap: .cgSessionEventTap)
        DockSwipe.makeEnvelope()!.post(tap: .cgSessionEventTap)
    }
    post(.began, 0)
    for i in 1...15 { post(.changed, Double(i) * 0.02); usleep(8000) }
    post(.ended, 0.3, 1.0)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let recipe = args.first else { print("usage: AnimProbe key|timed D|vel V T|velnoenv V T"); exit(2) }
let p1 = args.count > 1 ? Double(args[1])! : 0
let p2 = args.count > 2 ? Double(args[2])! : 0

func perform(_ dir: Int) {
    switch recipe {
    case "key": postKey(dir > 0)
    case "phys": postPhys(dir)
    case "key2": postKey(dir > 0); usleep(60_000); postKey(dir > 0)
    case "timed": postTimed(dir, duration: p1)
    case "vel": postVel(dir, velocity: p1, travel: p2, envelopes: true)
    case "velnoenv": postVel(dir, velocity: p1, travel: p2, envelopes: false)
    default: print("unknown recipe"); exit(2)
    }
}

// MARK: - Run

let content = try await SCShareableContent.current
let display = content.displays[0]
let cfg = SCStreamConfiguration()
cfg.width = W; cfg.height = H
cfg.minimumFrameInterval = CMTime(value: 1, timescale: 120)
cfg.pixelFormat = kCVPixelFormatType_32BGRA
cfg.showsCursor = false
cfg.queueDepth = 8
let rec = Recorder()
let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: cfg, delegate: nil)
try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: DispatchQueue(label: "cap", qos: .userInteractive))
try await stream.startCapture()

let startIdx = Spaces.cursorDisplay()?.currentIndex ?? 0
let count = Spaces.cursorDisplay()?.spaceIDs.count ?? 2
let firstDir = startIdx + 1 < count ? 1 : -1

try await Task.sleep(nanoseconds: 500_000_000)
let tA = CACurrentMediaTime() - rec.t0
perform(firstDir)
try await Task.sleep(nanoseconds: 1_600_000_000)
let midIdx = Spaces.cursorDisplay()?.currentIndex ?? -1
let tB = CACurrentMediaTime() - rec.t0
perform(-firstDir)
try await Task.sleep(nanoseconds: 1_600_000_000)
let endIdx = Spaces.cursorDisplay()?.currentIndex ?? -1
let tEnd = CACurrentMediaTime() - rec.t0
try await stream.stopCapture()

print("recipe=\(args.joined(separator: " ")) index \(startIdx) -> \(midIdx) -> \(endIdx)  (frames: \(rec.frames.count))")

func analyze(_ label: String, from a: Double, to b: Double) {
    let seg = rec.frames.filter { $0.t >= a - 0.1 && $0.t < b }
    guard seg.count > 2 else { print("\(label): too few frames"); return }
    let first = seg.first!.gray, last = seg.last!.gray
    let thr = 1.0
    let moving = seg.filter { diff($0.gray, first) > thr && diff($0.gray, last) > thr }
    let startT = seg.first { diff($0.gray, first) > thr }?.t ?? a
    let endT = seg.last { diff($0.gray, last) > thr }?.t ?? startT
    print(String(format: "%@: latency %.0f ms, motion %.0f ms, %d in-between frames", label,
                 (startT - a) * 1000, (endT - startT) * 1000, moving.count))
    var line = "   t(ms) shift lum: "
    var prevShift: Int? = nil, reversals = 0, lastDelta = 0
    for f in seg where f.t >= startT - 0.02 && f.t <= endT + 0.03 {
        let s = shift(f.gray, first)
        line += String(format: "[%.0f %d %.0f] ", (f.t - a) * 1000, s, lum(f.gray))
        if let p = prevShift { let d = s - p; if d != 0 { if lastDelta != 0 && (d > 0) != (lastDelta > 0) { reversals += 1 }; lastDelta = d } }
        prevShift = s
    }
    print(line)
    let lums = seg.map { lum($0.gray) }
    let baseLum = min(lum(first), lum(last))
    let dips = lums.filter { $0 < baseLum * 0.6 }.count
    print("   direction reversals: \(reversals), dark frames: \(dips)")
    let sheet = seg.filter { $0.t >= startT - 0.02 && $0.t <= endT + 0.03 }
    let path = FileManager.default.currentDirectoryPath + "/sheet-\(args.joined(separator: "_"))-\(label).png"
    savePNG(Array(sheet.prefix(36)), to: path)
}
analyze("fwd", from: tA, to: tB)
analyze("back", from: tB, to: tEnd)
