import Foundation

/// A destination for log entries.
///
/// Engines receive fully-formed `LogEntry` values and decide how to render,
/// persist, or forward them. Conformers must be safe to call from any thread
/// (`Sendable`); the registry never serialises calls for you.
///
/// Backwards-compatible string-based methods (`info`/`warn`/`error`) are still
/// available via default implementations, but new engines should override
/// ``log(_:)`` for full structured access.
public protocol LogEngine: AnyObject, Sendable {
    /// Receive a fully-structured log entry.
    func log(_ entry: LogEntry)

    /// Legacy info-level entry point. Default implementation forwards to
    /// ``log(_:)``.
    func info(message: String)

    /// Legacy warn-level entry point. Default implementation forwards to
    /// ``log(_:)``.
    func warn(message: String)

    /// Legacy error-level entry point. Default implementation forwards to
    /// ``log(_:)``.
    func error(message: String)

    /// Stable identifier for the engine instance. Used by the registry to
    /// remove engines by identity rather than by index. Defaults to the
    /// runtime type name.
    var engineID: String { get }

    /// Lowest level this engine accepts. Entries below the threshold are
    /// dropped before any work happens. Defaults to ``LogLevel/trace``
    /// (accept everything).
    var minimumLevel: LogLevel { get }
}

public extension LogEngine {
    var engineID: String { String(describing: type(of: self)) }
    var minimumLevel: LogLevel { .trace }

    func info(message: String) {
        log(LogEntry(level: .info, message: message))
    }

    func warn(message: String) {
        log(LogEntry(level: .warning, message: message))
    }

    func error(message: String) {
        log(LogEntry(level: .error, message: message))
    }
}
