// Session-level event tap that swallows the Spaces shortcuts before the Dock
// sees them and performs the switch at the user's chosen speed instead.
// Runs on the main run loop; everything it touches is main-thread state.

import AppKit
import CoreGraphics

final class KeyInterceptor {
    static let shared = KeyInterceptor()

    private(set) var isRunning = false
    private var tap: CFMachPort?
    private var shortcuts = SystemShortcuts.load()
    /// Key code whose keyDown we swallowed; its keyUp is swallowed too so the
    /// frontmost app never receives an orphan release.
    private var claimedKeyCode: Int64?

    private init() {
        // Pick up edited shortcuts when the user leaves System Settings.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.bundleIdentifier == "com.apple.systempreferences" { self?.reloadShortcuts() }
        }
    }

    func reloadShortcuts() {
        shortcuts = SystemShortcuts.load()
    }

    /// Installs the tap. Fails without Accessibility permission.
    @discardableResult
    func start() -> Bool {
        if let tap {
            if !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
            return true
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: mask,
                                          callback: keyInterceptorCallback,
                                          userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        else { return false }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        isRunning = true
        return true
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passthrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            claimedKeyCode = nil
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return passthrough
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyUp {
            guard claimedKeyCode == keyCode else { return passthrough }
            claimedKeyCode = nil
            return nil
        }

        let settings = Settings.shared
        guard type == .keyDown, settings.enabled else { return passthrough }

        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        if let direction = moveDirection(keyCode: keyCode, flags: flags) {
            // Native Spaces shortcuts don't auto-repeat; swallow repeats silently.
            if isRepeat { return claimedKeyCode == keyCode ? nil : passthrough }
            guard SpaceSwitcher.shared.move(direction, settings: settings) else { return passthrough }
            claimedKeyCode = keyCode
            return nil
        }

        if settings.handleDesktopShortcuts,
           let index = shortcuts.desktops.firstIndex(where: { $0?.matches(keyCode: keyCode, flags: flags) == true }) {
            if isRepeat { return claimedKeyCode == keyCode ? nil : passthrough }
            guard SpaceSwitcher.shared.jump(toDesktop: index + 1, settings: settings) else { return passthrough }
            claimedKeyCode = keyCode
            return nil
        }

        return passthrough
    }

    private func moveDirection(keyCode: Int64, flags: CGEventFlags) -> Int? {
        if shortcuts.moveLeft?.matches(keyCode: keyCode, flags: flags) == true { return -1 }
        if shortcuts.moveRight?.matches(keyCode: keyCode, flags: flags) == true { return 1 }
        return nil
    }
}

private func keyInterceptorCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                    userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    KeyInterceptor.shared.handle(type: type, event: event)
}
