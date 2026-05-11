import Foundation
import SwiftMoLogger

/// Ships log entries to Datadog's HTTP intake API.
///
/// API reference:
/// https://docs.datadoghq.com/api/latest/logs/#send-logs
public final class DatadogLogEngine: HTTPLogShipper {
    public enum Site: String, Sendable {
        case us1, us3, us5, eu1, ap1, us1FedRamp

        var host: String {
            switch self {
            case .us1: return "http-intake.logs.datadoghq.com"
            case .us3: return "http-intake.logs.us3.datadoghq.com"
            case .us5: return "http-intake.logs.us5.datadoghq.com"
            case .eu1: return "http-intake.logs.datadoghq.eu"
            case .ap1: return "http-intake.logs.ap1.datadoghq.com"
            case .us1FedRamp: return "http-intake.logs.ddog-gov.com"
            }
        }
    }

    public init(
        apiKey: String,
        site: Site = .us1,
        service: String,
        source: String = "swift",
        ddtags: [String: String] = [:]
    ) {
        let endpoint = URL(string: "https://\(site.host)/api/v2/logs")!
        let configuration = Configuration(
            endpoint: endpoint,
            headers: [
                "DD-API-KEY": apiKey,
                "Content-Type": "application/json"
            ],
            batchSize: 100,
            flushInterval: 5,
            maxRetries: 3
        )
        super.init(
            engineID: "swiftmologger.remote.datadog",
            minimumLevel: .info,
            configuration: configuration,
            body: DatadogLogEngine.makeBody(service: service, source: source, ddtags: ddtags)
        )
    }

    private static func makeBody(service: String, source: String, ddtags: [String: String]) -> BodyBuilder {
        let baseTags = ddtags.map { "\($0.key):\($0.value)" }.sorted().joined(separator: ",")
        let formatter = ISO8601DateFormatter()
        return { entries in
            let payload = entries.map { entry -> [String: Any] in
                var record: [String: Any] = [
                    "service": service,
                    "ddsource": source,
                    "message": entry.message,
                    "status": DatadogLogEngine.datadogStatus(for: entry.level),
                    "timestamp": formatter.string(from: entry.timestamp),
                    "thread": entry.threadName,
                    "source.file": entry.source.fileName,
                    "source.function": entry.source.function,
                    "source.line": entry.source.line
                ]
                if let tag = entry.tag {
                    var tags = baseTags
                    if !tags.isEmpty { tags += "," }
                    tags += "tag:\(tag.domain)"
                    record["ddtags"] = tags
                }
                if !entry.metadata.isEmpty {
                    record["extra"] = entry.metadata.storage.mapValues { $0.description }
                }
                return record
            }
            return try JSONSerialization.data(withJSONObject: payload)
        }
    }

    private static func datadogStatus(for level: LogLevel) -> String {
        switch level {
        case .trace: return "trace"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .warning: return "warn"
        case .error: return "error"
        case .critical: return "critical"
        case .fault: return "emergency"
        }
    }
}
