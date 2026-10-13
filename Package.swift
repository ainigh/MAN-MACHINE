// swift-tools-version: 6.0
import PackageDescription

var targets: [Target] = [
    // Pure logic. Foundation only. Builds and tests on Linux and macOS.
    .target(name: "MpmCore", swiftSettings: [.swiftLanguageMode(.v6)]),
    // The macOS app shell. SwiftUI + AppKit. Never contains protocol logic.
    .executableTarget(name: "MachinePromptsMan", dependencies: ["MpmCore"],
                      swiftSettings: [.swiftLanguageMode(.v6)]),
    .testTarget(name: "MpmCoreTests", dependencies: ["MpmCore"]),
]

#if os(macOS)
// Host tests need the app target, which only builds on macOS once the UI exists (tasks/03).
targets.append(.testTarget(name: "MachinePromptsManTests", dependencies: ["MachinePromptsMan", "MpmCore"],
                           swiftSettings: [.swiftLanguageMode(.v6)]))
#endif

let package = Package(
    name: "MachinePromptsMan",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MpmCore", targets: ["MpmCore"]),
        .executable(name: "MachinePromptsMan", targets: ["MachinePromptsMan"]),
    ],
    targets: targets
)
