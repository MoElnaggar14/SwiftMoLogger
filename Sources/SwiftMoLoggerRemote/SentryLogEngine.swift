import Foundation
import SwiftMoLogger

/// Ships log entries to a Sentry-compatible `envelope` endpoint as messages
/// (not events). Pair with the official Sentry SDK if you also want crashes
/// — this engine is purely for logs.
public final class SentryLogEngine: HTTPLogShipper {
    public init(dsn: URL, release: String? = nil, environment: String? = nil) {
        precondition(dsn.scheme == "https" || dsn.scheme == "http", "Sentry DSN must be http(s)")
        let configuration = Configuration(
            endpoint: SentryLogEngine.envelopeURL(from: dsn),
            headers: SentryLogEngine.authHeaders(for: dsn),
            batchSize: 25,
            flushInterval: 5,
            maxRetries: 3
        )
        super.init(
            engineID: "swiftmologger.remote.sentry",
            minimumLevel: .warning,
            configuration: configuration,
            body: SentryLogEngine.makeBody(release: release, environment: environment)
        )
    }

    private static func makeBody(release: String?, environment: String?) -> BodyBuilder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return { entries in
            var payload = Data()
            // Envelope header
            let header: [String: Any] = ["sent_at": ISO8601DateFormatter().string(from: Date())]
            payload.append(try JSONSerialization.data(withJSONObject: header))
            payload.append(0x0A)
            for entry in entries {
                var item: [String: Any] = [
                    "type": "message",
                    "logger": "SwiftMoLogger",
                    "level": SentryLogEngine.sentryLevel(for: entry.level),
                    "timestamp": ISO8601DateFormatter().string(from: entry.timestamp),
                    "message": entry.message
                ]
                if let tag = entry.tag {
                    item["tags"] = ["tag": tag.rawValue, "domain": tag.domain]
                }
                if !entry.metadata.isEmpty {
                    item["extra"] = entry.metadata.storage.mapValues { $0.description }
                }
                if let release = release { item["release"] = release }
                if let environment = environment { item["environment"] = environment }
                let itemHeader: [String: Any] = ["type": "event", "content_type": "application/json"]
                payload.append(try JSONSerialization.data(withJSONObject: itemHeader))
                payload.append(0x0A)
                payload.append(try JSONSerialization.data(withJSONObject: item))
                payload.append(0x0A)
            }
            return payload
        }
    }

    private static func sentryLevel(for level: LogLevel) -> String {
        switch level {
        case .trace, .debug: return "debug"
        case .info, .notice: return "info"
        case .warning: return "warning"
        case .error: return "error"
        case .critical, .fault: return "fatal"
        }
    }

    private static func envelopeURL(from dsn: URL) -> URL {
        // DSN format: https://<key>@o<org>.ingest.sentry.io/<project>
        var components = URLComponents(url: dsn, resolvingAgainstBaseURL: false)!
        components.user = nil
        components.password = nil
        let projectID = dsn.pathComponents.last ?? "0"
        components.path = "/api/\(projectID)/envelope/"
        return components.url!
    }

    private static func authHeaders(for dsn: URL) -> [String: String] {
        let key = dsn.user ?? ""
        let sentryAuth = "Sentry sentry_version=7, sentry_client=swiftmologger/1.0, sentry_key=\(key)"
        return [
            "X-Sentry-Auth": sentryAuth,
            "Content-Type": "application/x-sentry-envelope"
        ]
    }
}
