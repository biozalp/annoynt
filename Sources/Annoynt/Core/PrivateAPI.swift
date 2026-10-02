// Undocumented CGEvent fields and private SkyLight (CGS) functions.
//
// macOS has no public API for Spaces. Everything here is reverse-engineered
// and is the main fragility point of the app: if a macOS update breaks space
// switching, start looking here and in DockSwipe.swift.
//
// Field numbers come from the community CGSInternal headers and the
// InstantSpaceSwitcher / Space Rabbit projects (macOS 27 fields).

import CoreGraphics
import Darwin

// MARK: - CGEvent fields

let kCGSEventTypeField            = CGEventField(rawValue: 55)!
let kCGEventGestureHIDType        = CGEventField(rawValue: 110)!
let kCGEventGestureSwipeMask      = CGEventField(rawValue: 115)!
let kCGEventGestureSwipeMotion    = CGEventField(rawValue: 123)!
let kCGEventGestureSwipeProgress  = CGEventField(rawValue: 124)!
let kCGEventGesturePositionX      = CGEventField(rawValue: 125)!
let kCGEventGesturePositionY      = CGEventField(rawValue: 126)!
let kCGEventGestureSwipeVelocityX = CGEventField(rawValue: 129)!
let kCGEventGestureSwipeVelocityY = CGEventField(rawValue: 130)!
let kCGEventGesturePhase          = CGEventField(rawValue: 132)!
/// macOS 27: must mirror `kCGEventGesturePhase`.
let kCGEventGesturePhase2         = CGEventField(rawValue: 134)!
/// macOS 27: gesture flavor, 3 = dock primary.
let kCGEventGestureFlavor         = CGEventField(rawValue: 138)!
/// macOS 27: `mach_absolute_time()` as a double.
let kCGEventGestureTimestamp      = CGEventField(rawValue: 169)!

/// macOS 27 validates dock swipes against a serialized IOHID payload stored
/// under this field. It can't be set with the field setters; it's appended to
/// the flattened event bytes instead (see `DockSwipe.attachIOHIDPayload`).
let kCGEventIOHIDPayloadField: UInt16 = 4205

// MARK: - Constants

let kIOHIDEventTypeDockSwipe: Int64 = 23
let kCGSEventGesture: Int64         = 29
let kCGSEventDockControl: Int64     = 30
let kGestureMotionHorizontal: Int64 = 1

let kIOHIDEventTypeVelocity: UInt32          = 9
let kIOHIDEventTypeFluidTouchGesture: UInt32 = 23
let kIOHIDGestureFlavorDockPrimary: UInt16   = 3

// MARK: - SkyLight functions

typealias CGSConnectionID = Int32
typealias CGSSpaceID = UInt64

private typealias FnMainConnection = @convention(c) () -> CGSConnectionID
private typealias FnActiveSpace    = @convention(c) (CGSConnectionID) -> CGSSpaceID
private typealias FnDisplaySpaces  = @convention(c) (CGSConnectionID, CFString?) -> Unmanaged<CFArray>?

private let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

private func loadSymbol<T>(_ name: String) -> T? {
    guard let ptr = dlsym(rtldDefault, name) else { return nil }
    return unsafeBitCast(ptr, to: T.self)
}

private let cgsMainConnectionID: FnMainConnection? = loadSymbol("CGSMainConnectionID")
private let cgsGetActiveSpace: FnActiveSpace? = loadSymbol("CGSGetActiveSpace")
private let cgsCopyManagedDisplaySpaces: FnDisplaySpaces? = loadSymbol("CGSCopyManagedDisplaySpaces")

enum SkyLight {
    static var isAvailable: Bool {
        cgsMainConnectionID != nil && cgsCopyManagedDisplaySpaces != nil
    }

    static func activeSpace() -> CGSSpaceID {
        guard let conn = cgsMainConnectionID, let active = cgsGetActiveSpace else { return 0 }
        return active(conn())
    }

    /// One dictionary per display: "Display Identifier", "Current Space", "Spaces".
    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let conn = cgsMainConnectionID, let copy = cgsCopyManagedDisplaySpaces else { return [] }
        let cid = conn()
        guard cid != 0 else { return [] }
        return copy(cid, nil)?.takeRetainedValue() as? [[String: Any]] ?? []
    }
}
