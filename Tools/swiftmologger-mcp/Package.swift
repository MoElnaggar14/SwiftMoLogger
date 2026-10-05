// swift-tools-version:6.1
// The MCP server lives in its own package so apps that depend on SwiftMoLogger
// never resolve the MCP SDK and its dependencies.

import PackageDescription

let package = Package(
    name: "swiftmologger-mcp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "swiftmologger-mcp", targets: ["swiftmologger-mcp"])
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.11.0")
    ],
    targets: [
        // Domain: devices, ring buffers, queries, the LiveSink line protocol and the
        // Bonjour client. No MCP dependency, so it's testable without a network.
        .target(
            name: "SwiftMoLoggerMCPCore",
            dependencies: [.product(name: "SwiftMoLogger", package: "SwiftMoLogger")]
        ),
        // The MCP tool catalogue and handlers.
        .target(
            name: "SwiftMoLoggerMCPServer",
            dependencies: [
                "SwiftMoLoggerMCPCore",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .executableTarget(
            name: "swiftmologger-mcp",
            dependencies: [
                "SwiftMoLoggerMCPCore",
                "SwiftMoLoggerMCPServer",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(
            name: "SwiftMoLoggerMCPTests",
            dependencies: [
                "SwiftMoLoggerMCPCore",
                "SwiftMoLoggerMCPServer",
                .product(name: "MCP", package: "swift-sdk")
            ]
        )
    ]
)
