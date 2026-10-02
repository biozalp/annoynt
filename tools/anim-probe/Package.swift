// swift-tools-version: 6.0
// Calibration harness: screen-records space switches at 120 fps and reports
// slide duration / flicker. Shares the gesture code with the app via symlinks.
import PackageDescription
let package = Package(
    name: "AnimProbe",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "AnimProbe", path: "Sources/AnimProbe",
                                swiftSettings: [.swiftLanguageMode(.v5)])]
)
