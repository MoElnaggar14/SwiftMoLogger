// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "SwiftMoLogger",
    defaultLocalization: .init("en"),
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "SwiftMoLogger", targets: ["SwiftMoLogger"]),
        .library(name: "SwiftMoLoggerUI", targets: ["SwiftMoLoggerUI"]),
        .library(name: "SwiftMoLoggerNetwork", targets: ["SwiftMoLoggerNetwork"]),
        .library(name: "SwiftMoLoggerRemote", targets: ["SwiftMoLoggerRemote"]),
        .library(name: "SwiftMoLoggerDiagnostics", targets: ["SwiftMoLoggerDiagnostics"]),
        .library(name: "SwiftMoLoggerTesting", targets: ["SwiftMoLoggerTesting"]),
        .library(name: "SwiftMoLoggerSugar", targets: ["SwiftMoLoggerSugar"]),
        .library(name: "SwiftMoLoggerSwiftLog", targets: ["SwiftMoLoggerSwiftLog"]),
        .executable(name: "swiftmologger-inspector", targets: ["SwiftMoLoggerInspector"]),
    ],
    dependencies: [
        // Wide range (Swift 5.9 through 6.2) so the macro target never forces a
        // swift-syntax version that conflicts with other packages in an app.
        // CI builds against both the pinned and the newest resolvable version.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "509.0.0"..<"605.0.0"),
        // Only linked by the SwiftMoLoggerSwiftLog product.
        .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
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
            dependencies: ["SwiftMoLogger"],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "SwiftMoLoggerTesting",
            dependencies: ["SwiftMoLogger"]
        ),
        .target(
            name: "SwiftMoLoggerSugar",
            dependencies: ["SwiftMoLogger", "SwiftMoLoggerMacros"]
        ),
        .target(
            name: "SwiftMoLoggerSwiftLog",
            dependencies: [
                "SwiftMoLogger",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "SwiftMoLoggerInspector",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v5)]
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
            dependencies: ["SwiftMoLogger", "SwiftMoLoggerTesting"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SwiftMoLoggerUITests",
            dependencies: ["SwiftMoLoggerUI"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SwiftMoLoggerNetworkTests",
            dependencies: ["SwiftMoLoggerNetwork", "SwiftMoLoggerTesting"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SwiftMoLoggerRemoteTests",
            dependencies: ["SwiftMoLoggerRemote"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SwiftMoLoggerSwiftLogTests",
            dependencies: ["SwiftMoLoggerSwiftLog", "SwiftMoLoggerTesting"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SwiftMoLoggerMacrosTests",
            dependencies: [
                "SwiftMoLoggerMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ],
    swiftLanguageModes: [.v6]
)
