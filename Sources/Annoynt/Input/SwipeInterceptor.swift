// Replaces horizontal three/four-finger trackpad swipes between spaces with a
// switch at the user's chosen speed.
//
// macOS turns the physical swipe into private DockSwipe events. We swallow the
// swipe as it begins, read its direction from the first sample that clearly
// moves, and post our own swipe instead — the Dock then plays its shortened
// animation exactly as for the keyboard shortcuts. Reversing the fingers
// without lifting them undoes the switch, as macOS allows natively.
//
// Two taps, split by event type: DockControl (30) carries the swipe and is
// rare, so it's always on; the generic Gesture envelopes (29) fire for every
// finger movement, so that tap only runs while a swipe is claimed.

import CoreGraphics
import Foundation

final class SwipeInterceptor {
    static let shared = SwipeInterceptor()

    /// Progress before a sample's sign is trusted as intent, not touch wobble.
    private static let directionThreshold = 0.05
    /// Travel back from the furthest point that undoes the switch.
    private static let reversalThreshold = 0.2

    private var dockTap: CFMachPort?
    private var envelopeTap: CFMachPort?

    private var tracking = false
    /// Direction already switched for this gesture (0 = none yet), in physical
    /// sign: positive = towards the space on the right.
    private var intent = 0
    private var extreme = 0.0

    @discardableResult
    func start() -> Bool {
        if let dockTap {
            if !CGEvent.tapIsEnabled(tap: dockTap) { CGEvent.tapEnable(tap: dockTap, enable: true) }
            return true
        }
        guard let dock = makeTap(subtype: kCGSEventDockControl),
              let envelope = makeTap(subtype: kCGSEventGesture) else { return false }
        dockTap = dock
        envelopeTap = envelope
        CGEvent.tapEnable(tap: dock, enable: true)
        return true
    }

    private func makeTap(subtype: Int64) -> CFMachPort? {
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(1) << CGEventMask(subtype),
                                          callback: swipeInterceptorCallback,
                                          userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: false)
        return tap
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        // `.tapDisabledByUserInput` is also delivered when *we* toggle the
        // envelope tap, so only a timeout means macOS shut a tap down on us.
        if type == .tapDisabledByUserInput { return passthrough }
        if type == .tapDisabledByTimeout {
            endTracking()
            if let dockTap { CGEvent.tapEnable(tap: dockTap, enable: true) }
            return passthrough
        }

        if DockSwipe.isSynthetic(event) { return passthrough }

        let subtype = event.getIntegerValueField(kCGSEventTypeField)
        if subtype == kCGSEventGesture { return tracking ? nil : passthrough }

        guard subtype == kCGSEventDockControl,
              event.getIntegerValueField(kCGEventGestureHIDType) == kIOHIDEventTypeDockSwipe,
              event.getIntegerValueField(kCGEventGestureSwipeMotion) == kGestureMotionHorizontal
        else { return passthrough }

        switch GesturePhase(rawValue: event.getIntegerValueField(kCGEventGesturePhase)) {
        case .began:
            let settings = Settings.shared
            // Inside Mission Control the swipe scrolls its Spaces bar — leave it native.
            guard settings.enabled, settings.handleTrackpad, !Spaces.isOverviewActive() else {
                return passthrough
            }
            tracking = true
            intent = 0
            extreme = 0
            if let envelopeTap { CGEvent.tapEnable(tap: envelopeTap, enable: true) }
            return nil

        case .changed where tracking:
            let progress = event.getDoubleValueField(kCGEventGestureSwipeProgress)
            if intent != 0, (progress - extreme) * Double(intent) > 0 { extreme = progress }
            if let sign = requestedSign(progress: progress) {
                intent = sign
                extreme = progress
                SpaceSwitcher.shared.move(sign)
            }
            return nil

        case .ended where tracking:
            // A very quick flick can end before any Changed sample moved enough.
            if intent == 0 {
                let velocity = event.getDoubleValueField(kCGEventGestureSwipeVelocityX)
                if velocity != 0 { SpaceSwitcher.shared.move(velocity > 0 ? 1 : -1) }
            }
            endTracking()
            // macOS 27's Dock needs to see the gesture close; pass the Ended on
            // with its motion zeroed so it can't trigger a switch of its own.
            if DockSwipe.isAugmented {
                event.setDoubleValueField(kCGEventGestureSwipeVelocityX, value: 0)
                event.setDoubleValueField(kCGEventGestureSwipeVelocityY, value: 0)
                event.setDoubleValueField(kCGEventGestureSwipeProgress, value: 0)
                return passthrough
            }
            return nil

        case .cancelled where tracking:
            endTracking()
            return nil

        default:
            return tracking ? nil : passthrough
        }
    }

    /// Direction to switch now, if any: the first move past the threshold, or a
    /// reversal far enough back from the furthest point reached.
    private func requestedSign(progress: Double) -> Int? {
        if intent == 0 {
            guard abs(progress) >= Self.directionThreshold else { return nil }
            return progress > 0 ? 1 : -1
        }
        let travelBack = (extreme - progress) * Double(intent)
        return travelBack >= Self.reversalThreshold ? -intent : nil
    }

    private func endTracking() {
        tracking = false
        intent = 0
        extreme = 0
        if let envelopeTap { CGEvent.tapEnable(tap: envelopeTap, enable: false) }
    }
}

private func swipeInterceptorCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                      userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    SwipeInterceptor.shared.handle(type: type, event: event)
}

