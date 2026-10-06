import Foundation
import OSLog
import SwiftMoLogger

/// One entry from the unified log (`os_log`, `Logger`), as included in bug reports.
///
/// Apple frameworks and third-party SDKs log here rather than through SwiftMoLogger,
/// so these entries explain failures raised inside URLSession, Core Data or an SDK.
public struct SystemLogEntry: Sendable, Equatable {
    public let date: Date
    public let level: LogLevel
    public let subsystem: String
    public let category: String
    public let message: String

    public init(date: Date, level: LogLevel, subsystem: String, category: String, message: String) {
        self.date = date
        self.level = level
        self.subsystem = subsystem
        self.category = category
        self.message = message
    }
}

/// Where ``BugReporter`` reads unified-log entries from. Inject a fake in tests.
public protocol SystemLogSource: Sendable {
    /// Entries this process logged since `date`, oldest first.
    func entries(since date: Date) throws -> [SystemLogEntry]
}

/// This process's unified log, read through `OSLogStore`. iOS only lets an app read
/// its own process, which is exactly what a bug report needs.
///
/// Reading can take a second or more, so generate reports off the main thread.
public struct OSLogStoreSource: SystemLogSource {
    public init() {}

    public func entries(since date: Date) throws -> [SystemLogEntry] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store.getEntries(at: store.position(date: date))
            .compactMap { $0 as? OSLogEntryLog }
            .map { entry in
                SystemLogEntry(
                    date: entry.date,
                    level: Self.map(entry.level),
                    subsystem: entry.subsystem,
                    category: entry.category,
                    message: entry.composedMessage
                )
            }
    }

    static func map(_ level: OSLogEntryLog.Level) -> LogLevel {
        switch level {
        case .debug: .debug
        case .info: .info
        case .notice, .undefined: .notice
        case .error: .error
        case .fault: .fault
        @unknown default: .notice
        }
    }
}

/// Whether and how ``BugReporter`` adds the unified log as `system-log.txt`.
public struct SystemLogOptions: Sendable {
    /// How far back to read, in seconds.
    public var window: TimeInterval
    public var source: any SystemLogSource
    /// Applied to every message before it's written.
    public var redactor: Redactor
    /// The file keeps the newest entries that fit; older ones are counted, not written.
    public var maxBytes: Int

    public init(
        window: TimeInterval = 300,
        source: any SystemLogSource = OSLogStoreSource(),
        redactor: Redactor = Redactor(),
        maxBytes: Int = 1_000_000
    ) {
        self.window = window
        self.source = source
        self.redactor = redactor
        self.maxBytes = maxBytes
    }

    /// The text of `system-log.txt`: one redacted line per entry, newest entries kept
    /// within ``maxBytes``, with a first line saying how many older ones were left out.
    func render(_ entries: [SystemLogEntry]) -> String {
        let time = ISO8601DateFormatter()
        time.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var kept: [String] = []
        var bytes = 0
        for entry in entries.reversed() {
            let origin = [entry.subsystem, entry.category].filter { !$0.isEmpty }.joined(separator: " ")
            let message = redactor.redact(entry.message).output
            let line = "\(time.string(from: entry.date)) \(entry.level.description) [\(origin)] \(message)"
            let size = line.utf8.count + 1
            if bytes + size > maxBytes { break }
            bytes += size
            kept.append(line)
        }
        let omitted = entries.count - kept.count
        let header = omitted > 0 ? ["… \(omitted) earlier entries left out to stay under \(maxBytes) bytes"] : []
        return (header + kept.reversed()).joined(separator: "\n")
    }
}
