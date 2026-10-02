import Foundation
import Observation

struct SpeedPreset: Identifiable {
    let name: String
    let duration: TimeInterval
    var id: String { name }

    static let all = [
        SpeedPreset(name: "Instant", duration: 0),
        SpeedPreset(name: "Fast", duration: 0.05),
        SpeedPreset(name: "Smooth", duration: 0.12),
        SpeedPreset(name: "Relaxed", duration: 0.3),
    ]
}

/// User preferences, persisted in UserDefaults. Main-thread only.
@Observable
final class Settings {
    static let shared = Settings()

    /// Longest slide the speed curve can produce; macOS's own is ~0.8 s.
    static let maxDuration: TimeInterval = SpeedCurve.longest

    /// Off = Annoynt steps aside and macOS plays its own animation.
    var enabled: Bool { didSet { defaults.set(enabled, forKey: Keys.enabled) } }
    /// Target slide duration in seconds; below `SpeedCurve.shortest` = instant.
    var duration: TimeInterval { didSet { defaults.set(duration, forKey: Keys.duration) } }
    /// Also speed up three/four-finger trackpad swipes between spaces.
    var handleTrackpad: Bool { didSet { defaults.set(handleTrackpad, forKey: Keys.trackpad) } }
    /// Also handle "Switch to Desktop N" shortcuts.
    var handleDesktopShortcuts: Bool { didSet { defaults.set(handleDesktopShortcuts, forKey: Keys.desktopShortcuts) } }
    /// Escape hatch if a macOS build interprets the synthetic swipe direction
    /// the other way round.
    var reverseDirection: Bool { didSet { defaults.set(reverseDirection, forKey: Keys.reverse) } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "enabled"
        static let duration = "duration"
        static let trackpad = "handleTrackpad"
        static let desktopShortcuts = "handleDesktopShortcuts"
        static let reverse = "reverseDirection"
    }

    private init() {
        defaults.register(defaults: [
            Keys.enabled: true,
            Keys.duration: 0.12,
            Keys.trackpad: true,
            Keys.desktopShortcuts: true,
            Keys.reverse: false,
        ])
        enabled = defaults.bool(forKey: Keys.enabled)
        duration = min(max(defaults.double(forKey: Keys.duration), 0), Self.maxDuration)
        handleTrackpad = defaults.bool(forKey: Keys.trackpad)
        handleDesktopShortcuts = defaults.bool(forKey: Keys.desktopShortcuts)
        reverseDirection = defaults.bool(forKey: Keys.reverse)
    }
}
