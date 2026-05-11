import Foundation

/// Immutable record of a single log event.
///
/// Carries everything an engine needs to render, filter, persist, or forward
/// the message without re-deriving context. Designed for value-semantics so it
/// is safe to hand across actor boundaries.
public struct LogEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let tag: LogTag?
    public let metadata: LogMetadata
    public let source: SourceLocation
    public let threadName: String

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        message: String,
        tag: LogTag? = nil,
        metadata: LogMetadata = LogMetadata(),
        source: SourceLocation = SourceLocation(),
        threadName: String = LogEntry.currentThreadName()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.tag = tag
        self.metadata = metadata
        self.source = source
        self.threadName = threadName
    }

    /// Best-effort current-thread label. Cheap on the hot path: avoids
    /// `Thread.current.description`'s allocation by checking the main-thread
    /// fast path first and falling back to the thread's name.
    public static func currentThreadName() -> String {
        if Thread.isMainThread { return "main" }
        let name = Thread.current.name ?? ""
        return name.isEmpty ? "thread" : name
    }

    /// Human-readable single-line rendering used by `SystemLogger` and console
    /// viewers. Kept stable so log scrapers can rely on it.
    public func formatted() -> String {
        var output = "\(level.emoji) "
        if let tag = tag {
            output += "\(tag.rawValue) "
        }
        output += message
        if !metadata.isEmpty {
            let pairs = metadata.storage
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value.description)" }
                .joined(separator: " ")
            output += " {\(pairs)}"
        }
        return output
    }
}
