import Foundation
import SwiftMoLogger

/// Ships log entries to a Grafana Loki push endpoint
/// (`POST /loki/api/v1/push`).
public final class LokiLogEngine: HTTPLogShipper {
    public init(endpoint: URL, labels: [String: String] = ["job": "swiftmologger"], basicAuth: (user: String, password: String)? = nil) {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let auth = basicAuth {
            let token = Data("\(auth.user):\(auth.password)".utf8).base64EncodedString()
            headers["Authorization"] = "Basic \(token)"
        }
        let configuration = Configuration(
            endpoint: endpoint,
            headers: headers,
            batchSize: 100,
            flushInterval: 5,
            maxRetries: 3
        )
        super.init(
            engineID: "swiftmologger.remote.loki",
            minimumLevel: .info,
            configuration: configuration,
            body: LokiLogEngine.makeBody(staticLabels: labels)
        )
    }

    private static func makeBody(staticLabels: [String: String]) -> BodyBuilder {
        return { entries in
            // Group entries by their derived label set so they share a stream.
            var streams: [String: (labels: [String: String], values: [[String]])] = [:]
            for entry in entries {
                var labels = staticLabels
                labels["level"] = entry.level.description
                if let tag = entry.tag { labels["tag"] = tag.domain }
                let key = labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
                let ns = String(Int64(entry.timestamp.timeIntervalSince1970 * 1_000_000_000))
                let line = entry.formatted()
                streams[key, default: (labels, [])].values.append([ns, line])
            }
            let body: [String: Any] = [
                "streams": streams.values.map { stream in
                    ["stream": stream.labels, "values": stream.values]
                }
            ]
            return try JSONSerialization.data(withJSONObject: body)
        }
    }
}
