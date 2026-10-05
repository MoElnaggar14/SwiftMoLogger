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

    /// Stable identifier for the engine instance. The registry uses it to
    /// remove engines by identity, and adding an engine replaces any engine
    /// with the same ID. Defaults to one ID per instance, so two engines of
    /// the same type both stay registered; return a fixed ID to opt into
    /// replace-by-ID.
    var engineID: String { get }

    /// Lowest level this engine accepts. Entries below the threshold are
    /// dropped before any work happens. Defaults to ``LogLevel/trace``
    /// (accept everything).
    var minimumLevel: LogLevel { get }

    /// Writes or sends anything the engine has buffered. Called by
    /// ``EngineRegistry/flush()``, e.g. when the app moves to the background or
    /// before a bug report. Defaults to doing nothing; engines that buffer
    /// (``FileLogEngine``, remote shippers) override it, and decorators forward it.
    func flush()
}

public extension LogEngine {
    var engineID: String {
        "\(String(describing: type(of: self)))#\(UInt(bitPattern: ObjectIdentifier(self).hashValue))"
    }
    var minimumLevel: LogLevel { .trace }

    func flush() {}

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
