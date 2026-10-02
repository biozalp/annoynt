// Performs space switches at the user's chosen speed by posting one synthetic
// swipe per step; the Dock plays its own (shortened) animation for it.
// Main thread only.

import AppKit
import CoreGraphics

final class SpaceSwitcher {
    static let shared = SpaceSwitcher()

    /// Moves issued from `pendingOrigin` that the window server may not have
    /// reported yet. Lets rapid repeated presses step correctly and stop at the
    /// last space instead of reading a stale "current space".
    private var pendingOrigin: CGSSpaceID?
    private var pendingDelta = 0
    private var pendingExpiry = Date.distantPast
    /// When the current slide finishes. A swipe that lands mid-animation makes
    /// the Dock fall back to its slow native settle, so it goes out instant.
    private var animatingUntil = Date.distantPast

    /// Moves one space left (-1) or right (+1) on the display under the cursor.
    /// Returns `false` when the layout can't be read, so the caller lets the
    /// native gesture/shortcut through instead.
    @discardableResult
    func move(_ direction: Int, settings: Settings = .shared) -> Bool {
        guard let display = Spaces.cursorDisplay(), display.currentIndex >= 0 else { return false }

        let target = effectiveIndex(on: display) + direction
        // At the first/last space: do nothing (natively this is a slow bounce).
        guard display.spaceIDs.indices.contains(target) else { return true }

        register(delta: direction, on: display, settings: settings)
        post(direction: direction, steps: 1, settings: settings)
        return true
    }

    /// Jumps to Mission Control's "Desktop N" (1-based). Returns `false` when
    /// the desktop doesn't exist or lives on another display.
    @discardableResult
    func jump(toDesktop number: Int, settings: Settings = .shared) -> Bool {
        let desktops = Spaces.userDesktops()
        guard desktops.indices.contains(number - 1),
              let display = Spaces.cursorDisplay(), display.currentIndex >= 0,
              let targetIndex = display.spaceIDs.firstIndex(of: desktops[number - 1])
        else { return false }

        let steps = targetIndex - effectiveIndex(on: display)
        guard steps != 0 else { return true }

        register(delta: steps, on: display, settings: settings)
        post(direction: steps > 0 ? 1 : -1, steps: abs(steps), settings: settings)
        return true
    }

    private func post(direction: Int, steps: Int, settings: Settings) {
        let sign = DockSwipe.sign(for: direction, userReversed: settings.reverseDirection)
        // Several swipes in a row would each play an animation; a multi-space
        // jump, or a press during a running slide, goes straight to the target.
        let animate = steps == 1 && Date() >= animatingUntil
        let velocity = animate ? SpeedCurve.velocity(for: settings.duration) : SpeedCurve.instantVelocity
        if animate { animatingUntil = Date().addingTimeInterval(settings.duration + 0.03) }
        for _ in 0..<steps {
            guard let events = DockSwipe.makeSwipe(sign: sign, velocity: velocity) else { return }
            events.forEach { $0.post(tap: .cgSessionEventTap) }
        }
    }

    // MARK: - Bookkeeping

    private func effectiveIndex(on display: DisplaySpaces) -> Int {
        let current = display.spaceIDs[display.currentIndex]
        guard pendingOrigin == current, Date() < pendingExpiry else { return display.currentIndex }
        return display.currentIndex + pendingDelta
    }

    private func register(delta: Int, on display: DisplaySpaces, settings: Settings) {
        let current = display.spaceIDs[display.currentIndex]
        if pendingOrigin != current || Date() >= pendingExpiry {
            pendingOrigin = current
            pendingDelta = 0
        }
        pendingDelta += delta
        pendingExpiry = Date().addingTimeInterval(settings.duration + 0.4)
    }
}
