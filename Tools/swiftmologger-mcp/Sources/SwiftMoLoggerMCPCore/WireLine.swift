import Foundation
import SwiftMoLogger

/// The first line LiveSink sends on a connection (protocol version 2), or the
/// version-1 banner sent by SwiftMoLogger 3.x.
public struct Hello: Sendable, Equatable, Codable {
    public let version: Int
    public let app: String
    public let appVersion: String?
    public let os: String?
    public let connectedAt: String?

    public init(version: Int, app: String, appVersion: String? = nil, os: String? = nil, connectedAt: String? = nil) {
        self.version = version
        self.app = app
        self.appVersion = appVersion
        self.os = os
        self.connectedAt = connectedAt
    }
}

/// One newline-delimited line of the LiveSink protocol.
///
/// Lines with a `kind` are control messages; lines without one are encoded
/// `LogEntry` values. Unknown kinds are skipped, which is what lets newer devices
/// add message types without breaking this server (see `LiveSink.protocolVersion`).
public enum WireLine: Sendable, Equatable {
    case hello(Hello)
    case entry(LogEntry)
    case unknownControl(kind: String)
    case invalid

    /// The protocol version this server understands.
    public static let supportedProtocolVersion = 2

    public static func decode(_ data: Data) -> WireLine {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .invalid
        }
        if object["service"] as? String == "SwiftMoLogger.LiveSink" {
            return .hello(Hello(
                version: object["version"] as? Int ?? 1,
                app: object["app"] as? String ?? "?",
                appVersion: object["app_version"] as? String,
                os: object["os"] as? String,
                connectedAt: (object["connected_at"] ?? object["started_at"]) as? String
            ))
        }
        if let kind = object["kind"] as? String {
            return .unknownControl(kind: kind)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        guard let entry = try? decoder.decode(LogEntry.self, from: data) else { return .invalid }
        return .entry(entry)
    }
}

/// Splits a byte stream into newline-terminated lines, keeping any partial line.
public struct LineSplitter: Sendable {
    private var buffer = Data()

    public init() {}

    /// Appends `chunk` and returns every complete line it finished.
    public mutating func append(_ chunk: Data) -> [Data] {
        buffer.append(chunk)
        var lines: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
