// swift-tools-version:5.9
// ThoughtMeter builds with Swift Package Manager only — no Xcode required.
// The .app bundle is assembled by scripts/build.sh. See CONTRIBUTING.md.
import PackageDescription

let package = Package(
    name: "ThoughtMeter",
    platforms: [.macOS(.v14)],
    targets: [
        // All tracking, aggregation, and persistence logic. No AppKit, fully testable.
        .target(
            name: "ThoughtMeterKit",
            path: "apps/macos/Sources/ThoughtMeterKit"
        ),
        // The menu bar application (SwiftUI + AppKit glue).
        .executableTarget(
            name: "ThoughtMeter",
            dependencies: ["ThoughtMeterKit"],
            path: "apps/macos/Sources/ThoughtMeterApp"
        ),
        // Chrome Native Messaging protocol + host decision logic.
        .target(
            name: "NativeHostCore",
            dependencies: ["ThoughtMeterKit"],
            path: "helpers/chrome-native-host/Sources/NativeHostCore"
        ),
        // The native messaging host executable Chrome launches.
        .executableTarget(
            name: "thoughtmeter-native-host",
            dependencies: ["NativeHostCore"],
            path: "helpers/chrome-native-host/Sources/thoughtmeter-native-host"
        ),
        // Zero-dependency test runner (Command Line Tools ship neither XCTest
        // nor swift-testing; see CONTRIBUTING.md "Testing").
        .executableTarget(
            name: "thoughtmeter-tests",
            dependencies: ["ThoughtMeterKit", "NativeHostCore"],
            path: "apps/macos/Tests"
        ),
    ]
)
