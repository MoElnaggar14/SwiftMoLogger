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
        .library(name: "SwiftMoLogger", targets: ["SwiftMoLogger"]),
        .library(name: "SwiftMoLoggerUI", targets: ["SwiftMoLoggerUI"]),
        .library(name: "SwiftMoLoggerNetwork", targets: ["SwiftMoLoggerNetwork"]),
        .library(name: "SwiftMoLoggerRemote", targets: ["SwiftMoLoggerRemote"]),
        .library(name: "SwiftMoLoggerDiagnostics", targets: ["SwiftMoLoggerDiagnostics"]),
        .library(name: "SwiftMoLoggerTesting", targets: ["SwiftMoLoggerTesting"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftMoLogger",
            dependencies: [],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "SwiftMoLoggerUI",
            dependencies: ["SwiftMoLogger"]
        ),
        .target(
            name: "SwiftMoLoggerNetwork",
            dependencies: ["SwiftMoLogger"]
        ),
        .target(
            name: "SwiftMoLoggerRemote",
            dependencies: ["SwiftMoLogger"]
        ),
        .target(
            name: "SwiftMoLoggerDiagnostics",
            dependencies: ["SwiftMoLogger"]
        ),
        .target(
            name: "SwiftMoLoggerTesting",
            dependencies: ["SwiftMoLogger"]
        ),
        .testTarget(
            name: "SwiftMoLoggerTests",
            dependencies: ["SwiftMoLogger", "SwiftMoLoggerTesting"]
        ),
        .testTarget(
            name: "SwiftMoLoggerUITests",
            dependencies: ["SwiftMoLoggerUI"]
        ),
        .testTarget(
            name: "SwiftMoLoggerNetworkTests",
            dependencies: ["SwiftMoLoggerNetwork", "SwiftMoLoggerTesting"]
        ),
        .testTarget(
            name: "SwiftMoLoggerRemoteTests",
            dependencies: ["SwiftMoLoggerRemote"]
        ),
    ]
)
