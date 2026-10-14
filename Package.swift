// swift-tools-version: 6.0
import PackageDescription

let v6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "MachinePromptsMan",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MpmCore", targets: ["MpmCore"]),
        .executable(name: "MachinePromptsMan", targets: ["MachinePromptsMan"]),
    ],
    targets: [
        // Pure logic. Foundation only. Builds and tests on Linux and macOS.
        .target(name: "MpmCore", swiftSettings: v6),
        // The host: persistence, clocks, the controller, model adapters. Foundation and Observation only,
        // so it builds and tests on Linux too. Lives in Sources/MachinePromptsMan/Host (CLAUDE.md layering).
        .target(name: "MpmHost", dependencies: ["MpmCore"], path: "Sources/MachinePromptsMan/Host",
                swiftSettings: v6),
        // The macOS app shell: SwiftUI + AppKit views only. Never contains protocol logic.
        .executableTarget(name: "MachinePromptsMan", dependencies: ["MpmCore", "MpmHost"],
                          path: "Sources/MachinePromptsMan", exclude: ["Host"], swiftSettings: v6),
        .testTarget(name: "MpmCoreTests", dependencies: ["MpmCore"]),
        .testTarget(name: "MachinePromptsManTests", dependencies: ["MpmHost", "MpmCore"], swiftSettings: v6),
    ]
)
