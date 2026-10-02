// Read-only queries over the current Spaces layout.

import AppKit
import CoreGraphics

struct DisplaySpaces {
    let identifier: String
    let spaceIDs: [CGSSpaceID]
    let currentIndex: Int
}

enum Spaces {
    /// Spaces of the display under the mouse cursor — the display that both the
    /// native Ctrl+Arrow shortcut and a synthetic dock swipe act on. Falls back
    /// to the display holding the globally active space.
    static func cursorDisplay() -> DisplaySpaces? {
        let displays = SkyLight.managedDisplaySpaces().compactMap(parse)
        if let uuid = displayUUIDUnderCursor(),
           let match = displays.first(where: { identifier($0.identifier, matches: uuid) }) {
            return match
        }
        let active = SkyLight.activeSpace()
        return displays.first { $0.currentIndex >= 0 && $0.spaceIDs[$0.currentIndex] == active }
    }

    /// User desktops (type 0) across all displays, in Mission Control's
    /// "Desktop N" numbering. Fullscreen app spaces are not numbered.
    static func userDesktops() -> [CGSSpaceID] {
        SkyLight.managedDisplaySpaces().flatMap { display -> [CGSSpaceID] in
            let spaces = display["Spaces"] as? [[String: Any]] ?? []
            return spaces.compactMap { space in
                guard (space["type"] as? NSNumber)?.intValue ?? 0 == 0 else { return nil }
                return (space["id64"] as? NSNumber)?.uint64Value
            }
        }
    }

    /// Whether Mission Control (or another full-screen overview) is up. Its
    /// marker is a display-sized overlay window: owned by WindowManager at
    /// layer 18/19 on macOS 27, by the Dock at layer 18 before that.
    static func isOverviewActive() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let screenSizes = NSScreen.screens.map(\.frame.size)
        return windows.contains { window in
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue else { return false }
            if DockSwipe.isAugmented {
                guard owner == "WindowManager", layer == 18 || layer == 19,
                      let dict = window[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: dict) else { return false }
                return screenSizes.contains { abs($0.width - bounds.width) <= 1 && abs($0.height - bounds.height) <= 1 }
            }
            return owner == "Dock" && layer == 18
        }
    }

    private static func parse(_ display: [String: Any]) -> DisplaySpaces? {
        guard let identifier = display["Display Identifier"] as? String,
              let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber,
              let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
        let ids = spaces.compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
        return DisplaySpaces(identifier: identifier,
                             spaceIDs: ids,
                             currentIndex: ids.firstIndex(of: current.uint64Value) ?? -1)
    }

    /// Some systems report "Main" instead of the primary display's UUID.
    private static func identifier(_ identifier: String, matches uuid: String) -> Bool {
        identifier == "Main" ? uuidString(for: CGMainDisplayID()) == uuid : identifier == uuid
    }

    private static func displayUUIDUnderCursor() -> String? {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return nil }
        return uuidString(for: id)
    }

    private static func uuidString(for display: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}
