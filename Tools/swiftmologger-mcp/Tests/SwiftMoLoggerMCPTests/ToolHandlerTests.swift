import Foundation
import MCP
import SwiftMoLogger
import Testing
@testable import SwiftMoLoggerMCPCore
@testable import SwiftMoLoggerMCPServer

@Suite("MCP tools")
struct ToolHandlerTests {
    func text(_ result: CallTool.Result) -> String {
        result.content.compactMap { content in
            if case let .text(text, _, _) = content { return text }
            return nil
        }.joined(separator: "\n")
    }

    @Test func catalogueIsReadOnly() {
        #expect(Set(ToolCatalog.all.map(\.name)) == ["list_devices", "search_logs", "get_entry", "wait_for", "network_requests"])
        #expect(ToolCatalog.all.allSatisfy { $0.annotations.readOnlyHint == true })
    }

    @Test func listDevicesExplainsWhatToDoWhenEmpty() async {
        let result = await ToolHandler(hub: DeviceHub()).call(.init(name: "list_devices"))
        #expect(text(result).contains("NSBonjourServices"))
        #expect(result.isError != true)
    }

    @Test func searchLogsRendersCompactLines() async {
        let hub = DeviceHub()
        await hub.connect(sending: [Wire.entry("Payment failed", level: .error, tag: .api, metadata: ["code": 402])])
        let result = await ToolHandler(hub: hub).call(.init(name: "search_logs", arguments: ["min_level": "error"]))
        let line = text(result)
        #expect(line.contains("#1"))
        #expect(line.contains("ERROR"))
        #expect(line.contains("Payment failed"))
        #expect(line.contains("code=402"))
        #expect(line.contains("CheckoutViewModel.swift:88"))
        #expect(result.structuredContent?.objectValue?["entries"]?.arrayValue?.count == 1)
    }

    @Test func rejectsInvalidArguments() async {
        let handler = ToolHandler(hub: DeviceHub())
        let level = await handler.call(.init(name: "search_logs", arguments: ["min_level": "loud"]))
        #expect(level.isError == true)
        let since = await handler.call(.init(name: "search_logs", arguments: ["since": "soon"]))
        #expect(since.isError == true)
        let id = await handler.call(.init(name: "get_entry", arguments: ["id": "nope"]))
        #expect(id.isError == true)
        let unknown = await handler.call(.init(name: "delete_everything"))
        #expect(unknown.isError == true)
    }

    @Test func getEntryShowsSourceAndNeighbours() async {
        let hub = DeviceHub()
        let entries = [Wire.entry("before"), Wire.entry("target", level: .error), Wire.entry("after")]
        await hub.connect(sending: entries)
        let result = await ToolHandler(hub: hub).call(
            .init(name: "get_entry", arguments: ["id": .string(entries[1].id.uuidString), "context": 1])
        )
        let body = text(result)
        #expect(body.contains("▶"))
        #expect(body.contains("before"))
        #expect(body.contains("after"))
        #expect(body.contains("pay()"))
    }

    @Test func waitForReportsATimeout() async {
        let result = await ToolHandler(hub: DeviceHub()).call(
            .init(name: "wait_for", arguments: ["text": "never", "timeout_s": 1])
        )
        #expect(text(result).contains("Timed out"))
        #expect(result.structuredContent?.objectValue?["timedOut"]?.boolValue == true)
    }
}
