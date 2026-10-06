import Foundation
import MCP
import SwiftMoLogger
import SwiftMoLoggerMCPCore

/// The tool catalogue. Every tool is read-only: the agent can look, never change anything.
public enum ToolCatalog {
    static let readOnly = Tool.Annotations(readOnlyHint: true, destructiveHint: false, openWorldHint: false)

    static let filterProperties: [String: Value] = [
        "device": ["type": "string", "description": "Device name from list_devices. Omit for every device."],
        "min_level": [
            "type": "string",
            "enum": ["trace", "debug", "info", "notice", "warning", "error", "critical", "fault"],
            "description": "Lowest level to include."
        ],
        "tags": [
            "type": "array", "items": ["type": "string"],
            "description": "Tag domains or names, e.g. [\"network\", \"checkout\"]. `data` also matches `data.database`."
        ],
        "text": [
            "type": "string",
            "description": "Case-insensitive substring of the message or a metadata value. Prefix with `regex:` for a regular expression."
        ]
    ]

    public static let all: [Tool] = [
        Tool(
            name: "list_devices",
            description: """
            Lists the devices running a SwiftMoLogger debug build with LiveSink on the local network: \
            their app, connection state and how many entries are buffered. Call this first.
            """,
            inputSchema: ["type": "object", "properties": [:]],
            annotations: readOnly
        ),
        Tool(
            name: "search_logs",
            description: """
            Searches the log entries received from devices, newest last. With no filters it returns the latest entries \
            (a tail). Results are compact lines `#seq time LEVEL [Tag] message {metadata} File.swift:line`. \
            Use `after_seq` with the returned `next_seq` to fetch only newer entries.
            """,
            inputSchema: [
                "type": "object",
                "properties": .object(filterProperties.merging([
                    "since": ["type": "string", "description": "Relative (`90s`, `5m`, `2h`) or ISO 8601 date."],
                    "after_seq": ["type": "integer", "description": "Only entries newer than this sequence number."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 500, "description": "Default 50."]
                ]) { $1 })
            ],
            annotations: readOnly
        ),
        Tool(
            name: "get_entry",
            description: "Returns one entry in full (metadata, source location, thread) with the entries logged around it.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "The entry's id, from search_logs' structured results."],
                    "context": ["type": "integer", "minimum": 0, "maximum": 50, "description": "Entries before and after. Default 5."]
                ],
                "required": ["id"]
            ],
            annotations: readOnly
        ),
        Tool(
            name: "wait_for",
            description: """
            Waits for the next entry matching the filters, for example while the user reproduces a bug. \
            Only entries logged after the call count. Returns the entry, or reports a timeout.
            """,
            inputSchema: [
                "type": "object",
                "properties": .object(filterProperties.merging([
                    "timeout_s": ["type": "integer", "minimum": 1, "maximum": 120, "description": "Default 60."]
                ]) { $1 })
            ],
            annotations: readOnly
        ),
        Tool(
            name: "network_requests",
            description: """
            Lists HTTP requests logged by SwiftMoLogger's NetworkLogger: method, redacted URL, status, duration and errors.
            """,
            inputSchema: [
                "type": "object",
                "properties": [
                    "device": ["type": "string"],
                    "since": ["type": "string", "description": "Relative (`5m`) or ISO 8601 date."],
                    "failed_only": ["type": "boolean", "description": "Only status ≥ 400 and transport errors."],
                    "limit": ["type": "integer", "minimum": 1, "maximum": 500, "description": "Default 50."]
                ]
            ],
            annotations: readOnly
        )
    ]
}

/// Runs tool calls against a ``DeviceHub``.
public struct ToolHandler: Sendable {
    let hub: DeviceHub

    public init(hub: DeviceHub) {
        self.hub = hub
    }

    public func call(_ params: CallTool.Parameters, now: Date = Date()) async -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            switch params.name {
            case "list_devices": return try await listDevices()
            case "search_logs": return try await searchLogs(arguments, now: now)
            case "get_entry": return try await getEntry(arguments)
            case "wait_for": return try await waitFor(arguments, now: now)
            case "network_requests": return try await networkRequests(arguments, now: now)
            default: return failure("Unknown tool \(params.name).")
            }
        } catch let error as ArgumentError {
            return failure(error.message)
        } catch {
            return failure("\(error)")
        }
    }

    // MARK: - Tools

    private func listDevices() async throws -> CallTool.Result {
        let devices = await hub.devicesSummary()
        guard !devices.isEmpty else {
            return .init(content: [.plain("""
            No devices found. Run a Debug build that starts LiveSink, on the same Wi-Fi as this Mac, \
            with NSLocalNetworkUsageDescription and NSBonjourServices (_swiftmologger._tcp) in its Info.plist.
            """)])
        }
        let lines = devices.map { device in
            var line = "\(device.device): \(device.state.rawValue), \(device.buffered) entries"
            if let app = device.app { line += ", app \(app) \(device.appVersion ?? "")" }
            if let version = device.protocolVersion, version != WireLine.supportedProtocolVersion {
                line += " — speaks LiveSink protocol \(version); this server expects \(WireLine.supportedProtocolVersion)"
            }
            return line
        }
        return try .init(content: [.plain(lines.joined(separator: "\n"))], structuredContent: DevicesOutput(devices: devices))
    }

    private func searchLogs(_ arguments: [String: Value], now: Date) async throws -> CallTool.Result {
        let query = try Self.query(from: arguments, now: now)
        let result = await hub.search(query)
        var text = result.entries.map { Rendering.line($0, showDevice: query.device == nil) }.joined(separator: "\n")
        if text.isEmpty { text = "No matching entries." }
        if result.truncated { text += "\n(more entries matched; showing the newest \(result.entries.count))" }
        return try .init(
            content: [.plain(text)],
            structuredContent: SearchOutput(
                entries: result.entries.map(EntryOutput.init),
                nextSeq: result.nextSeq,
                truncated: result.truncated
            )
        )
    }

    private func getEntry(_ arguments: [String: Value]) async throws -> CallTool.Result {
        guard let idText = arguments["id"]?.stringValue, let id = UUID(uuidString: idText) else {
            throw ArgumentError("`id` must be an entry id (a UUID) from search_logs.")
        }
        let context = arguments["context"]?.intValue ?? 5
        guard let found = await hub.entry(id: id, context: context) else {
            return failure("No buffered entry has id \(idText). It may have been dropped from the buffer.")
        }
        let entry = found.entry.entry
        var lines = found.before.map { "  " + Rendering.line($0) }
        lines.append("▶ " + Rendering.line(found.entry, metadataLimit: .max))
        lines.append("    source: \(entry.source.file):\(entry.source.line) \(entry.source.function), thread \(entry.threadName)")
        lines += found.after.map { "  " + Rendering.line($0) }
        return try .init(
            content: [.plain(lines.joined(separator: "\n"))],
            structuredContent: EntryDetailOutput(
                entry: EntryOutput(found.entry),
                before: found.before.map(EntryOutput.init),
                after: found.after.map(EntryOutput.init)
            )
        )
    }

    private func waitFor(_ arguments: [String: Value], now: Date) async throws -> CallTool.Result {
        var query = try Self.query(from: arguments, now: now)
        query.since = nil
        query.afterSeq = nil
        let timeout = min(max(arguments["timeout_s"]?.intValue ?? 60, 1), 120)
        guard let stored = await hub.waitFor(query, timeout: .seconds(timeout)) else {
            return try .init(
                content: [.plain("Timed out after \(timeout) s with no matching entry.")],
                structuredContent: WaitOutput(entry: nil, timedOut: true)
            )
        }
        return try .init(
            content: [.plain(Rendering.line(stored, showDevice: true))],
            structuredContent: WaitOutput(entry: EntryOutput(stored), timedOut: false)
        )
    }

    private func networkRequests(_ arguments: [String: Value], now: Date) async throws -> CallTool.Result {
        let since = try arguments["since"]?.stringValue.map { text in
            guard let date = TimeExpression.date(from: text, now: now) else {
                throw ArgumentError("`since` must look like 90s, 5m, 2h or an ISO 8601 date.")
            }
            return date
        }
        let requests = await hub.networkRequests(
            device: arguments["device"]?.stringValue,
            since: since,
            failedOnly: arguments["failed_only"]?.boolValue ?? false,
            limit: arguments["limit"]?.intValue ?? 50
        )
        let text = requests.isEmpty
            ? "No HTTP requests logged. Requests appear when the app's URLSession uses SwiftMoLogger's NetworkLogger."
            : requests.map { request in
                let outcome = request.error.map { "✗ \($0)" } ?? "\(request.status ?? 0)"
                let duration = request.durationMS.map { "\(Int($0)) ms" } ?? ""
                return "#\(request.seq) \(request.method) \(request.url) → \(outcome) \(duration)"
            }.joined(separator: "\n")
        return try .init(content: [.plain(text)], structuredContent: RequestsOutput(requests: requests))
    }

    // MARK: - Arguments

    static func query(from arguments: [String: Value], now: Date) throws -> LogQuery {
        var query = LogQuery(limit: arguments["limit"]?.intValue ?? 50)
        query.device = arguments["device"]?.stringValue
        if let name = arguments["min_level"]?.stringValue {
            guard let level = LogLevel(name: name) else {
                throw ArgumentError("`min_level` must be one of trace, debug, info, notice, warning, error, critical, fault.")
            }
            query.minLevel = level
        }
        query.tags = arguments["tags"]?.arrayValue?.compactMap(\.stringValue) ?? []
        query.text = arguments["text"]?.stringValue
        if let since = arguments["since"]?.stringValue {
            guard let date = TimeExpression.date(from: since, now: now) else {
                throw ArgumentError("`since` must look like 90s, 5m, 2h or an ISO 8601 date.")
            }
            query.since = date
        }
        if let afterSeq = arguments["after_seq"]?.intValue, afterSeq >= 0 {
            query.afterSeq = UInt64(afterSeq)
        }
        return query
    }

    private func failure(_ message: String) -> CallTool.Result {
        .init(content: [.plain(message)], isError: true)
    }
}

struct ArgumentError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

// MARK: - Structured output

struct EntryOutput: Codable, Sendable {
    let seq: UInt64
    let id: String
    let device: String
    let session: Int
    let timestamp: String
    let level: String
    let tag: String?
    let message: String
    let metadata: [String: String]
    let source: String
    let thread: String

    init(_ stored: StoredEntry) {
        let entry = stored.entry
        seq = stored.seq
        id = entry.id.uuidString
        device = stored.device
        session = stored.session
        timestamp = entry.timestamp.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
        level = entry.level.description.lowercased()
        tag = entry.tag?.rawValue
        message = entry.message
        metadata = Rendering.metadataStrings(entry.metadata)
        source = "\(entry.source.file):\(entry.source.line)"
        thread = entry.threadName
    }
}

struct DevicesOutput: Codable, Sendable {
    let devices: [DeviceSummary]
}

struct RequestsOutput: Codable, Sendable {
    let requests: [NetworkRequest]
}

struct SearchOutput: Codable, Sendable {
    let entries: [EntryOutput]
    let nextSeq: UInt64?
    let truncated: Bool
}

struct EntryDetailOutput: Codable, Sendable {
    let entry: EntryOutput
    let before: [EntryOutput]
    let after: [EntryOutput]
}

struct WaitOutput: Codable, Sendable {
    let entry: EntryOutput?
    let timedOut: Bool
}

extension Tool.Content {
    /// Plain text with no annotations or metadata.
    static func plain(_ text: String) -> Self {
        .text(text: text, annotations: nil, _meta: nil)
    }
}
