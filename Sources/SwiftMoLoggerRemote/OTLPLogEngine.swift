import Foundation
import SwiftMoLogger

/// Ships log entries to any OpenTelemetry (OTLP/HTTP JSON) logs endpoint:
/// the OpenTelemetry Collector, Grafana, Honeycomb, Datadog, New Relic and others.
///
/// ```swift
/// let otlp = OTLPLogEngine(
///     endpoint: URL(string: "https://otel.example.com:4318/v1/logs")!,
///     serviceName: "shop-ios",
///     headers: ["Authorization": "Bearer …"],
///     resource: ["deployment.environment": "production"]
/// )
/// logging.registry.addEngine(RedactingLogEngine(wrapping: otlp))
/// ```
///
/// - Severity follows OpenTelemetry's table: trace 1, debug 5, info 9, notice 10,
///   warning 13, error 17, critical 21, fault 22.
/// - The message becomes the record body; metadata, the tag, the source location
///   and the thread name become attributes, plus `swift.task.name` inside a named task.
/// - Entries stamped by a ``TraceContext`` (`trace.id` and `span.id` metadata) fill
///   the record's `traceId` and `spanId`, so logs line up with backend traces.
///
/// JSON only: no protobuf dependency. Anything compiled into an app can be extracted,
/// so don't put an org-wide secret in `headers`; forward through your own backend instead.
public final class OTLPLogEngine: HTTPLogShipper, @unchecked Sendable {
    // @unchecked Sendable: this subclass adds no state, and HTTPLogShipper confines
    // its own to a serial queue.

    /// - Parameters:
    ///   - endpoint: The full logs URL, usually ending in `/v1/logs` (port 4318 for a collector).
    ///   - serviceName: The `service.name` resource attribute.
    ///   - headers: Sent with every request, e.g. an API key header.
    ///   - resource: Extra resource attributes, e.g. `deployment.environment`.
    public init(
        endpoint: URL,
        serviceName: String,
        headers: [String: String] = [:],
        resource: [String: String] = [:],
        minimumLevel: LogLevel = .info
    ) {
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        let configuration = Configuration(
            endpoint: endpoint,
            headers: allHeaders,
            batchSize: 100,
            flushInterval: 5,
            maxRetries: 3
        )
        var attributes = resource
        attributes["service.name"] = serviceName
        attributes["telemetry.sdk.name"] = "swiftmologger"
        attributes["telemetry.sdk.language"] = "swift"
        super.init(
            engineID: "swiftmologger.remote.otlp.\(HTTPLogShipper.endpointKey(endpoint))",
            minimumLevel: minimumLevel,
            configuration: configuration,
            body: OTLPLogEngine.makeBody(resource: attributes)
        )
    }

    static func makeBody(resource: [String: String]) -> BodyBuilder {
        // Captures only the Sendable [String: String]; JSON objects are built per batch.
        return { entries in
            let resourceAttributes = resource.sorted { $0.key < $1.key }
                .map { OTLPLogEngine.attribute($0.key, .string($0.value)) }
            let scopeLogs: [String: Any] = [
                "scope": ["name": "SwiftMoLogger"],
                "logRecords": entries.map(OTLPLogEngine.record)
            ]
            let resourceLogs: [String: Any] = [
                "resource": ["attributes": resourceAttributes],
                "scopeLogs": [scopeLogs]
            ]
            let body: [String: Any] = ["resourceLogs": [resourceLogs]]
            return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
    }

    // MARK: - Mapping

    /// Metadata keys a ``TraceContext`` stamps; they map to record fields, not attributes.
    private static let traceKeys: Set<String> = ["trace.id", "span.id", "trace.sampled"]

    static func record(_ entry: LogEntry) -> [String: Any] {
        let nanos = String(Int64((entry.timestamp.timeIntervalSince1970 * 1_000_000_000).rounded()))
        var attributes = entry.metadata.storage
            .filter { !traceKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { attribute($0.key, $0.value) }
        if let tag = entry.tag {
            attributes.append(attribute("swiftmologger.tag", .string(tag.rawValue)))
            attributes.append(attribute("swiftmologger.tag.domain", .string(tag.domain)))
        }
        attributes.append(attribute("code.file.path", .string(entry.source.file)))
        attributes.append(attribute("code.function.name", .string(entry.source.function)))
        attributes.append(attribute("code.line.number", .int(Int64(entry.source.line))))
        if !entry.threadName.isEmpty {
            attributes.append(attribute("thread.name", .string(entry.threadName)))
        }
        if let taskName = entry.taskName {
            attributes.append(attribute("swift.task.name", .string(taskName)))
        }

        var record: [String: Any] = [
            "timeUnixNano": nanos,
            "observedTimeUnixNano": nanos,
            "severityNumber": severityNumber(entry.level),
            "severityText": entry.level.description,
            "body": anyValue(.string(entry.message)),
            "attributes": attributes
        ]
        if case let .string(traceID)? = entry.metadata["trace.id"], isHex(traceID, length: 32) {
            record["traceId"] = traceID
            if case let .string(spanID)? = entry.metadata["span.id"], isHex(spanID, length: 16) {
                record["spanId"] = spanID
            }
            if case let .bool(sampled)? = entry.metadata["trace.sampled"] {
                record["flags"] = sampled ? 1 : 0
            }
        }
        return record
    }

    static func severityNumber(_ level: LogLevel) -> Int {
        switch level {
        case .trace: 1
        case .debug: 5
        case .info: 9
        case .notice: 10
        case .warning: 13
        case .error: 17
        case .critical: 21
        case .fault: 22
        }
    }

    static func attribute(_ key: String, _ value: LogMetadataValue) -> [String: Any] {
        ["key": key, "value": anyValue(value)]
    }

    /// An OTLP `AnyValue`. 64-bit integers are strings in OTLP/JSON.
    static func anyValue(_ value: LogMetadataValue) -> [String: Any] {
        switch value {
        case let .string(string): ["stringValue": string]
        case let .int(int): ["intValue": String(int)]
        case let .double(double) where double.isFinite: ["doubleValue": double]
        case let .double(double): ["stringValue": String(double)]
        case let .bool(bool): ["boolValue": bool]
        case let .array(values): ["arrayValue": ["values": values.map(anyValue)]]
        case let .dictionary(values):
            ["kvlistValue": ["values": values.sorted { $0.key < $1.key }.map { attribute($0.key, $0.value) }]]
        case .null: [:]
        }
    }

    private static func isHex(_ string: String, length: Int) -> Bool {
        string.count == length && string.allSatisfy(\.isHexDigit)
    }
}
