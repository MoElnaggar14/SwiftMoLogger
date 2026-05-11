// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftMoLogger",
    defaultLocalization: .init("en"),
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "SwiftMoLogger",
            targets: ["SwiftMoLogger"]
        ),
        .library(
            name: "SwiftMoLoggerUI",
            targets: ["SwiftMoLoggerUI"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftMoLogger",
            dependencies: []
        ),
        .target(
            name: "SwiftMoLoggerUI",
            dependencies: ["SwiftMoLogger"]
        ),
        .testTarget(
            name: "SwiftMoLoggerTests",
            dependencies: ["SwiftMoLogger"]
        ),
        .testTarget(
            name: "SwiftMoLoggerUITests",
            dependencies: ["SwiftMoLoggerUI"]
        ),
    ]
)
