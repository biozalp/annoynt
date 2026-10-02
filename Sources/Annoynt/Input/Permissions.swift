import AppKit
import ApplicationServices

enum Permissions {
    /// Accessibility covers both the keyboard event tap and posting gestures.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Annoynt to the Accessibility list.
    static func request() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
