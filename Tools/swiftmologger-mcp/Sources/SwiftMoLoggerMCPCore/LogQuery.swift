import Foundation
import SwiftMoLogger

/// An entry as the server stores it: the device's entry plus a server-wide sequence number.
public struct StoredEntry: Sendable, Equatable {
    /// Monotonic across the whole server, so agents can page with `after_seq`.
    public let seq: UInt64
    public let device: String
    /// Increments every time the device reconnects or the app relaunches.
    public let session: Int
    public let receivedAt: Date
    public let entry: LogEntry
}

/// A filter over stored entries. Every field is optional; an empty query matches everything.
public struct LogQuery: Sendable, Equatable {
    public var device: String?
    public var minLevel: LogLevel?
    /// Tag domains or names, matched case-insensitively; `data` matches `data.database`.
    public var tags: [String]
    /// Case-insensitive substring of the message or a metadata value. Prefix with `regex:` for a regular expression.
    public var text: String?
    public var since: Date?
    public var afterSeq: UInt64?
    public var limit: Int

    public init(
        device: String? = nil,
        minLevel: LogLevel? = nil,
        tags: [String] = [],
        text: String? = nil,
        since: Date? = nil,
        afterSeq: UInt64? = nil,
        limit: Int = 50
    ) {
        self.device = device
        self.minLevel = minLevel
        self.tags = tags
        self.text = text
        self.since = since
        self.afterSeq = afterSeq
        self.limit = min(max(limit, 1), 500)
    }

    public func matches(_ stored: StoredEntry) -> Bool {
        let entry = stored.entry
        if let device, stored.device != device { return false }
        if let minLevel, entry.level < minLevel { return false }
        if let afterSeq, stored.seq <= afterSeq { return false }
        if let since, entry.timestamp < since { return false }
        if !tags.isEmpty {
            guard let tag = entry.tag else { return false }
            let domain = tag.domain.lowercased()
            let name = tag.rawValue.lowercased()
            let matched = tags.contains { wanted in
                let wanted = wanted.lowercased()
                return domain == wanted || domain.hasPrefix(wanted + ".") || name.contains(wanted)
            }
            if !matched { return false }
        }
        if let text, !text.isEmpty, !Self.text(text, matches: entry) { return false }
        return true
    }

    private static func text(_ pattern: String, matches entry: LogEntry) -> Bool {
        let haystacks = [entry.message] + entry.metadata.storage.values.map(\.description)
        if pattern.hasPrefix("regex:") {
            guard let regex = try? Regex(String(pattern.dropFirst(6))).ignoresCase() else { return false }
            return haystacks.contains { $0.contains(regex) }
        }
        return haystacks.contains { $0.localizedCaseInsensitiveContains(pattern) }
    }
}

public enum TimeExpression {
    /// Parses a relative duration (`90s`, `5m`, `2h`, `1d`) back from `now`, or an ISO 8601 date.
    public static func date(from text: String, now: Date = Date()) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let unit = trimmed.last, let value = Double(trimmed.dropLast()), value >= 0 {
            let seconds: Double? = switch unit {
            case "s": value
            case "m": value * 60
            case "h": value * 3_600
            case "d": value * 86_400
            default: nil
            }
            if let seconds { return now.addingTimeInterval(-seconds) }
        }
        return try? Date(text, strategy: .iso8601)
    }
}
