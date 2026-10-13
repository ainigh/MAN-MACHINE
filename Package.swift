// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MachinePromptsMan",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MpmCore", targets: ["MpmCore"]),
        .executable(name: "MachinePromptsMan", targets: ["MachinePromptsMan"]),
    ],
    targets: [
        // Pure logic. Foundation only. Builds and tests on Linux and macOS.
        .target(name: "MpmCore", swiftSettings: [.swiftLanguageMode(.v6)]),
        // The macOS app shell. SwiftUI + AppKit. Never contains protocol logic.
        .executableTarget(name: "MachinePromptsMan", dependencies: ["MpmCore"],
                          swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "MpmCoreTests", dependencies: ["MpmCore"]),
    ]
)
