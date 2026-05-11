// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport

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
        .library(name: "SwiftMoLoggerSugar", targets: ["SwiftMoLoggerSugar"]),
        .executable(name: "swiftmologger-inspector", targets: ["SwiftMoLoggerInspector"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "509.0.0"),
    ],
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
        .target(
            name: "SwiftMoLoggerSugar",
            dependencies: ["SwiftMoLogger", "SwiftMoLoggerMacros"]
        ),
        .executableTarget(
            name: "SwiftMoLoggerInspector",
            dependencies: []
        ),
        .macro(
            name: "SwiftMoLoggerMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ]
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
        .testTarget(
            name: "SwiftMoLoggerMacrosTests",
            dependencies: [
                "SwiftMoLoggerMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ]
        ),
    ]
)
