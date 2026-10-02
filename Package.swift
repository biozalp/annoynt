// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Annoynt",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Annoynt",
            path: "Sources/Annoynt",
            swiftSettings: [
                // CGEvent tap callbacks and dlsym'd C function pointers don't fit
                // Swift 6 strict concurrency; everything that touches them is
                // confined to the main thread or the switcher's serial queue.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
