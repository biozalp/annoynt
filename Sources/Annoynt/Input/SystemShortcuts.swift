// Reads the user's Spaces shortcuts from System Settings
// (com.apple.symbolichotkeys), so Annoynt intercepts exactly the keys macOS
// would have handled — including custom bindings — and nothing else.
//
// Hotkey IDs: 79 = Move left a space, 81 = Move right a space,
// 118–127 = Switch to Desktop 1–10.

import CoreGraphics
import Foundation

struct KeyBinding: Equatable {
    let keyCode: Int64
    let modifiers: CGEventFlags

    static let relevantModifiers: CGEventFlags = [.maskControl, .maskCommand, .maskAlternate, .maskShift]

    func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode && flags.intersection(Self.relevantModifiers) == modifiers
    }
}

struct SystemShortcuts {
    var moveLeft: KeyBinding?
    var moveRight: KeyBinding?
    /// Index 0 = Desktop 1.
    var desktops: [KeyBinding?] = Array(repeating: nil, count: 10)

    private static let defaultLeft = KeyBinding(keyCode: 123, modifiers: .maskControl)
    private static let defaultRight = KeyBinding(keyCode: 124, modifiers: .maskControl)

    private enum Entry {
        case systemDefault, disabled, bound(KeyBinding)
    }

    static func load() -> SystemShortcuts {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        guard let hotkeys = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                      "com.apple.symbolichotkeys" as CFString) as? NSDictionary
        else {
            return SystemShortcuts(moveLeft: defaultLeft, moveRight: defaultRight)
        }

        func resolve(_ id: String, default fallback: KeyBinding?) -> KeyBinding? {
            switch entry(id, in: hotkeys) {
            case .systemDefault: fallback
            case .disabled: nil
            case .bound(let binding): binding
            }
        }

        var shortcuts = SystemShortcuts(moveLeft: resolve("79", default: defaultLeft),
                                        moveRight: resolve("81", default: defaultRight))
        for i in 0..<10 {
            // No default binding; never intercept a bare number key.
            if let binding = resolve(String(118 + i), default: nil), !binding.modifiers.isEmpty {
                shortcuts.desktops[i] = binding
            }
        }
        return shortcuts
    }

    /// Entry shape: { enabled = 1; value = { parameters = (ascii, keyCode, carbonMods); }; }
    private static func entry(_ id: String, in hotkeys: NSDictionary) -> Entry {
        guard let entry = hotkeys[id] as? NSDictionary else { return .systemDefault }
        if let enabled = entry["enabled"] as? NSNumber, enabled.intValue == 0 { return .disabled }

        guard let value = entry["value"] as? NSDictionary,
              let params = value["parameters"] as? [NSNumber], params.count >= 3
        else { return .systemDefault }

        let keyCode = params[1].int64Value
        guard keyCode != 65535, keyCode >= 0 else { return .disabled }
        return .bound(KeyBinding(keyCode: keyCode, modifiers: cgFlags(fromModifierMask: params[2].int64Value)))
    }

    /// Symbolic hotkeys store modifiers as device-independent NSEvent masks
    /// (e.g. 0x840000 = Control + Function); Function is ignored.
    private static func cgFlags(fromModifierMask raw: Int64) -> CGEventFlags {
        var flags: CGEventFlags = []
        if raw & 0x020000 != 0 { flags.insert(.maskShift) }
        if raw & 0x040000 != 0 { flags.insert(.maskControl) }
        if raw & 0x080000 != 0 { flags.insert(.maskAlternate) }
        if raw & 0x100000 != 0 { flags.insert(.maskCommand) }
        return flags
    }
}
