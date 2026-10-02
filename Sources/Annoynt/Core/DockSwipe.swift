// Builds the synthetic DockSwipe events the Dock turns into a space switch.
//
// A switch is posted as a complete swipe with near-zero finger travel and a
// chosen release velocity. The Dock reacts exactly as it does to a real
// trackpad flick: it plays its own space animation, shortened according to the
// velocity (see SpeedCurve), or snaps instantly when the velocity is extreme.
//
// Two recipes exist:
//   - macOS 27+: extra mirrored fields plus a serialized IOHID payload
//     (field 4205). Bare gestures are rejected.
//   - macOS 14–26: the original InstantSpaceSwitcher recipe.

import CoreGraphics
import Foundation

enum GesturePhase: Int64 {
    case began = 1
    case changed = 2
    case ended = 4
    case cancelled = 8
}

enum DockSwipe {
    static let isAugmented = ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27

    /// Finger travel of a synthetic swipe — near zero so the Dock animates from
    /// the release velocity alone, but representable in the 16.16 payload so
    /// the direction survives serialization.
    static let travel = 0.0001
    /// Release velocity far above the Dock's "snap" threshold.
    static let commitVelocity = 9999.0

    /// Stamped into `eventSourceUserData` of everything we post so our own
    /// trackpad interceptor lets it through.
    static let syntheticMarker: Int64 = 0x414E_4E59 // 'ANNY'

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == syntheticMarker
    }

    // MARK: - Direction

    /// Sign to apply to progress/velocity so the swipe moves in `direction`
    /// (+1 = next space, -1 = previous space).
    ///
    /// On macOS 27 the Dock interprets synthetic swipes through the "Natural
    /// scrolling" preference (measured by Space Rabbit on 27.0 seeds and
    /// release): with it on, positive progress moves *left*. The user can
    /// flip the result in settings if a future build changes this again.
    static func sign(for direction: Int, userReversed: Bool) -> Double {
        var s: Double = direction > 0 ? 1 : -1
        if isAugmented && naturalScrollingEnabled() { s = -s }
        if userReversed { s = -s }
        return s
    }

    static func naturalScrollingEnabled() -> Bool {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        return CFPreferencesCopyAppValue("com.apple.swipescrolldirection" as CFString,
                                         kCFPreferencesAnyApplication) as? Bool ?? true
    }

    // MARK: - Event construction

    /// One phase of a horizontal dock swipe. `progress` and `velocity` are signed.
    static func makeEvent(phase: GesturePhase, progress: Double, velocity: Double? = nil) -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }

        event.setIntegerValueField(kCGSEventTypeField, value: kCGSEventDockControl)
        event.setIntegerValueField(kCGEventGestureHIDType, value: kIOHIDEventTypeDockSwipe)
        event.setIntegerValueField(kCGEventGesturePhase, value: phase.rawValue)
        event.setIntegerValueField(kCGEventGestureSwipeMotion, value: kGestureMotionHorizontal)
        event.setDoubleValueField(kCGEventGestureSwipeProgress, value: progress)

        if let velocity {
            event.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: velocity)
            event.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: 0)
        }

        if isAugmented {
            event.setIntegerValueField(kCGEventGesturePhase2, value: phase.rawValue)
            event.setDoubleValueField(kCGEventGestureFlavor, value: Double(kIOHIDGestureFlavorDockPrimary))
            event.setDoubleValueField(kCGEventGestureTimestamp, value: Double(mach_absolute_time()))
            // The 27 Dock discards gestures whose position is exactly zero.
            event.setDoubleValueField(kCGEventGesturePositionX, value: 0.1)
        }

        return attachIOHIDPayload(to: event)
    }

    /// The companion "gesture" envelope event posted after each dock-control event.
    static func makeEnvelope() -> CGEvent? {
        guard let event = CGEvent(source: nil) else { return nil }
        event.setIntegerValueField(kCGSEventTypeField, value: kCGSEventGesture)
        return event
    }

    /// A complete swipe (all phases), built up front so an allocation failure
    /// never leaves the Dock with a Began and no Ended. Post in order.
    /// - Parameters:
    ///   - sign: from `sign(for:userReversed:)`.
    ///   - velocity: release velocity magnitude (see `SpeedCurve`).
    static func makeSwipe(sign: Double, velocity: Double) -> [CGEvent]? {
        let events = isAugmented ? makeAugmentedSwipe(sign: sign, velocity: velocity)
                                 : makeLegacySwipe(sign: sign, velocity: velocity)
        events?.forEach { $0.setIntegerValueField(.eventSourceUserData, value: syntheticMarker) }
        return events
    }

    private static func makeAugmentedSwipe(sign: Double, velocity: Double) -> [CGEvent]? {
        var events: [CGEvent] = []
        for phase in [GesturePhase.began, .changed, .ended] {
            guard let dock = makeEvent(phase: phase,
                                       progress: sign * travel,
                                       velocity: phase == .ended ? sign * velocity : nil),
                  let envelope = makeEnvelope() else { return nil }
            events += [dock, envelope]
        }
        return events
    }

    /// InstantSpaceSwitcher's pre-27 recipe: every phase carries a minimal
    /// progress and the velocity. Untested here (developed on macOS 27).
    private static func makeLegacySwipe(sign: Double, velocity: Double) -> [CGEvent]? {
        var events: [CGEvent] = []
        for phase in [GesturePhase.began, .changed, .ended] {
            guard let dock = CGEvent(source: nil) else { return nil }
            dock.setIntegerValueField(kCGSEventTypeField, value: kCGSEventDockControl)
            dock.setIntegerValueField(kCGEventGestureHIDType, value: kIOHIDEventTypeDockSwipe)
            dock.setIntegerValueField(kCGEventGesturePhase, value: phase.rawValue)
            dock.setIntegerValueField(kCGEventGestureSwipeMotion, value: kGestureMotionHorizontal)
            dock.setDoubleValueField(kCGEventGestureSwipeProgress, value: sign * Double(Float.leastNonzeroMagnitude))
            dock.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: sign * velocity)
            dock.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: sign * velocity)
            events.append(dock)
        }
        return events
    }

    // MARK: - IOHID payload (field 4205)

    /// Re-creates `event` with a serialized IOHID queue element appended under
    /// field 4205, mirroring the gesture fields already set on it.
    private static func attachIOHIDPayload(to event: CGEvent) -> CGEvent? {
        guard let flattened = event.data as Data?,
              // Serialization format version 2; bail rather than corrupt anything else.
              flattened.count >= 4, flattened.prefix(4) == Data([0, 0, 0, 2])
        else { return nil }

        let payload = iohidPayload(for: event)
        var bytes = flattened
        // Record header: big-endian length, then big-endian (tag 0 | field id).
        bytes.append(UInt8(payload.count >> 8))
        bytes.append(UInt8(payload.count & 0xFF))
        bytes.append(UInt8(kCGEventIOHIDPayloadField >> 8))
        bytes.append(UInt8(kCGEventIOHIDPayloadField & 0xFF))
        bytes.append(payload)

        return CGEvent(withDataAllocator: kCFAllocatorDefault, data: bytes as CFData)
    }

    /// Packed little-endian layout:
    ///   IOHIDSystemQueueElementHeader (28) + FluidTouchGesture (40) [+ Velocity (28)]
    private static func iohidPayload(for event: CGEvent) -> Data {
        let phase    = event.getIntegerValueField(kCGEventGesturePhase)
        let progress = event.getDoubleValueField(kCGEventGestureSwipeProgress)
        let posX     = event.getDoubleValueField(kCGEventGesturePositionX)
        let posY     = event.getDoubleValueField(kCGEventGesturePositionY)
        let velX     = event.getDoubleValueField(kCGEventGestureSwipeVelocityX)
        let velY     = event.getDoubleValueField(kCGEventGestureSwipeVelocityY)
        let motion   = event.getIntegerValueField(kCGEventGestureSwipeMotion)
        let mask     = event.getIntegerValueField(kCGEventGestureSwipeMask)
        let hasVelocity = velX != 0 || velY != 0 || phase == GesturePhase.ended.rawValue

        var p = Data()
        // Queue element header
        p.appendLE(event.timestamp != 0 ? UInt64(event.timestamp) : mach_absolute_time())
        p.appendLE(UInt64(0))                          // sender id
        p.appendLE(UInt32(0))                          // options
        p.appendLE(UInt32(0))                          // attribute length
        p.appendLE(UInt32(hasVelocity ? 2 : 1))        // event count

        // Fluid touch gesture
        p.appendLE(UInt32(40))                         // size
        p.appendLE(kIOHIDEventTypeFluidTouchGesture)   // type
        p.appendLE(UInt32((phase & 0xFF) << 24))       // options: phase in the high byte
        p.append(contentsOf: [0, 0, 0, 0])             // depth + reserved
        p.appendLE(fixed1616(posX))
        p.appendLE(fixed1616(posY))
        p.appendLE(Int32(0))                           // position z
        p.appendLE(UInt32(truncatingIfNeeded: mask))
        p.appendLE(UInt16(truncatingIfNeeded: motion))
        p.appendLE(kIOHIDGestureFlavorDockPrimary)
        p.appendLE(fixed1616(progress))

        if hasVelocity {
            p.appendLE(UInt32(28))
            p.appendLE(kIOHIDEventTypeVelocity)
            p.appendLE(UInt32(0))
            p.append(contentsOf: [1, 0, 0, 0])         // depth 1 + reserved
            p.appendLE(fixed1616(velX))
            p.appendLE(fixed1616(velY))
            p.appendLE(Int32(0))
        }
        return p
    }

    /// Signed 16.16 fixed point; tiny non-zero values keep their sign.
    private static func fixed1616(_ value: Double) -> Int32 {
        guard value.isFinite else { return 0 }
        let scaled = (value * 65536).rounded(.towardZero)
        let fixed = Int32(min(max(scaled, Double(Int32.min)), Double(Int32.max)))
        if fixed == 0 && value != 0 { return value > 0 ? 1 : -1 }
        return fixed
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
