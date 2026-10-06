import Foundation
import MCP
import SwiftMoLogger
import SwiftMoLoggerMCPCore
import SwiftMoLoggerMCPServer

/// swiftmologger-mcp: an MCP server (stdio) that lets coding agents read the live logs
/// of debug builds running SwiftMoLogger's LiveSink on the local network.
///
/// stdout carries JSON-RPC, so diagnostics go to stderr.
///
/// Environment:
/// - `SWIFTMOLOGGER_MCP_BUFFER`: entries kept per device (default 10000).
/// - `SWIFTMOLOGGER_MCP_REDACT`: set to `0` to pass entries through without redaction (default: redact).
/// - `SWIFTMOLOGGER_MCP_APPS`: comma-separated bundle identifiers to accept (default: any).
@main
struct SwiftMoLoggerMCP {
    static func main() async {
        let environment = ProcessInfo.processInfo.environment
        let capacity = environment["SWIFTMOLOGGER_MCP_BUFFER"].flatMap(Int.init) ?? 10_000
        let redactor: Redactor? = environment["SWIFTMOLOGGER_MCP_REDACT"] == "0" ? nil : Redactor()
        let allowedApps = environment["SWIFTMOLOGGER_MCP_APPS"].map { list in
            Set(list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        }

        let hub = DeviceHub(capacityPerDevice: capacity, redactor: redactor, allowedApps: allowedApps)
        let browser = LiveSinkBrowser()
        let events = browser.start()
        let pump = Task {
            for await event in events {
                await hub.handle(event)
            }
        }
        diagnostic("browsing for \(LiveSinkBrowser.serviceType); redaction \(redactor == nil ? "off" : "on")")

        let handler = ToolHandler(hub: hub)
        let server = Server(
            name: "swiftmologger",
            version: "0.1.0",
            title: "SwiftMoLogger",
            instructions: """
            Reads live logs from Apple-platform debug builds that run SwiftMoLogger's LiveSink on this Mac's \
            network. Start with list_devices, then search_logs (no filters is a tail). Use get_entry for full \
            detail around one entry, network_requests for HTTP failures, and wait_for while the user reproduces \
            a bug. Entries are redacted before they reach you unless the user turned redaction off.
            """,
            capabilities: .init(tools: .init(listChanged: false))
        )
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: ToolCatalog.all)
        }
        await server.withMethodHandler(CallTool.self) { params in
            await handler.call(params)
        }

        do {
            try await server.start(transport: StdioTransport())
            await server.waitUntilCompleted()
        } catch {
            diagnostic("server stopped: \(error)")
        }
        browser.stop()
        pump.cancel()
    }

    static func diagnostic(_ message: String) {
        FileHandle.standardError.write(Data("swiftmologger-mcp: \(message)\n".utf8))
    }
}
