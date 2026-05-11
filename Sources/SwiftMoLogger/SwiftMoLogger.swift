import Foundation

/// SwiftMoLogger — modern, thread-safe, multi-engine logging for Apple
/// platforms.
///
/// Designed around three principles:
///
/// 1. **Zero ceremony.** `SwiftMoLogger.info("hello")` works out of the box —
///    no `configure(…)`, no protocol gymnastics, no required setup.
/// 2. **No surprises in production.** Unlike v2, no log call ever silently
///    becomes a no-op in release builds; the only debug-gated method is the
///    explicit ``debug(_:tag:metadata:file:function:line:)``.
/// 3. **Structured all the way down.** Every call materialises a
///    ``LogEntry``; tag, level, metadata, and source location travel
///    together so downstream engines never have to re-parse a string.
public enum SwiftMoLogger {

    // MARK: - Generic entry-point

    /// Fully-typed entry point. The level-specific helpers below delegate
    /// here.
    public static func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        let registry = EngineRegistry.shared
        guard level >= registry.minimumLevel else { return }
        let entry = LogEntry(
            level: level,
            message: message(),
            tag: tag,
            metadata: metadata,
            source: SourceLocation(file: file, function: function, line: line, column: column)
        )
        registry.dispatch(entry)
    }

    // MARK: - Level helpers

    public static func trace(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard LogLevel.trace >= EngineRegistry.shared.minimumLevel else { return }
        log(.trace, message(), tag: tag, metadata: metadata, file: file, function: function, line: line)
    }

    public static func info(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard LogLevel.info >= EngineRegistry.shared.minimumLevel else { return }
        log(.info, message(), tag: tag, metadata: metadata, file: file, function: function, line: line)
    }

    public static func notice(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard LogLevel.notice >= EngineRegistry.shared.minimumLevel else { return }
        log(.notice, message(), tag: tag, metadata: metadata, file: file, function: function, line: line)
    }

    public static func warn(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard LogLevel.warning >= EngineRegistry.shared.minimumLevel else { return }
        log(.warning, message(), tag: tag, metadata: metadata, file: file, function: function, line: line)
    }

    public static func error(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        guard LogLevel.error >= EngineRegistry.shared.minimumLevel else { return }
        log(.error, message(), tag: tag, metadata: metadata, file: file, function: function, line: line)
    }

    /// Convenience for capturing a thrown error with its localised
    /// description plus any custom metadata.
    public static func error(
        _ error: Error,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        var enriched = metadata
        enriched["error_type"] = .string(String(describing: type(of: error)))
        enriched["error"] = .string(String(describing: error))
        log(.error, error.localizedDescription, tag: tag, metadata: enriched, file: file, function: function, line: line)
    }

    public static func critical(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.critical, message(), tag: tag, metadata: metadata, file: file, function: function, line: line)
    }

    public static func fault(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.fault, message(), tag: tag, metadata: metadata, file: file, function: function, line: line)
    }

    /// DEBUG-only logger. Body is stripped entirely from release builds — no
    /// argument evaluation, no allocation.
    public static func debug(
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        log(.debug, message(), tag: tag ?? .debug, metadata: metadata, file: file, function: function, line: line)
        #endif
    }

    /// Convenience used by ``MetricKitCrashReporter`` and external crash
    /// pipelines.
    public static func crash(
        _ message: @autoclosure () -> String,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        log(.critical, message(), tag: .crash, metadata: metadata, file: file, function: function, line: line)
    }

    // MARK: - Ambient context (task-local)

    /// Run `block` with `metadata` merged onto the current ambient context.
    /// Backed by `@TaskLocal` so concurrent `Task`s see their own context
    /// without interfering with each other.
    public static func withContext<T>(
        _ metadata: LogMetadata,
        _ block: () throws -> T
    ) rethrows -> T {
        let merged = LogContext.current.merging(metadata)
        return try LogContext.$current.withValue(merged, operation: block)
    }

    public static func withContext<T>(
        _ metadata: LogMetadata,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let merged = LogContext.current.merging(metadata)
        return try await LogContext.$current.withValue(merged, operation: block)
    }

    /// Read-only view of the active ambient context.
    public static var currentContext: LogMetadata {
        LogContext.current
    }

    // MARK: - Engine management

    public static func addEngine(_ engine: any LogEngine) {
        EngineRegistry.shared.addEngine(engine)
    }

    public static func removeEngine(at index: Int) {
        EngineRegistry.shared.removeEngine(at: index)
    }

    @discardableResult
    public static func removeEngine(id: String) -> Bool {
        EngineRegistry.shared.removeEngine(id: id)
    }

    public static func allEngines() -> [any LogEngine] {
        EngineRegistry.shared.allEngines()
    }

    /// v2 compatibility alias.
    @available(*, deprecated, renamed: "allEngines()")
    public static func getAllEngines() -> [any LogEngine] {
        allEngines()
    }

    /// v2 compatibility alias.
    @available(*, deprecated, renamed: "allEngines()")
    public static func getEngines() -> [any LogEngine] {
        allEngines()
    }

    public static var engineCount: Int {
        EngineRegistry.shared.engineCount
    }

    public static var minimumLevel: LogLevel {
        get { EngineRegistry.shared.minimumLevel }
        set { EngineRegistry.shared.minimumLevel = newValue }
    }

    public static func reset() {
        EngineRegistry.shared.reset()
    }

    /// Live `AsyncStream` of every entry passing through the registry.
    public static func stream(bufferSize: Int = 256) -> AsyncStream<LogEntry> {
        if !EngineRegistry.shared.allEngines().contains(where: { $0.engineID == LogStream.shared.engineID }) {
            EngineRegistry.shared.addEngine(LogStream.shared)
        }
        return LogStream.shared.subscribe(bufferSize: bufferSize)
    }
}

// MARK: - LogTagged convenience

/// Conformers automatically tag their own logs.
public protocol LogTagged {
    var logTag: LogTag { get }
}

public extension LogTagged {
    func logInfo(_ message: @autoclosure () -> String, metadata: LogMetadata = [:], file: String = #fileID, function: String = #function, line: Int = #line) {
        SwiftMoLogger.info(message(), tag: logTag, metadata: metadata, file: file, function: function, line: line)
    }

    func logWarn(_ message: @autoclosure () -> String, metadata: LogMetadata = [:], file: String = #fileID, function: String = #function, line: Int = #line) {
        SwiftMoLogger.warn(message(), tag: logTag, metadata: metadata, file: file, function: function, line: line)
    }

    func logError(_ message: @autoclosure () -> String, metadata: LogMetadata = [:], file: String = #fileID, function: String = #function, line: Int = #line) {
        SwiftMoLogger.error(message(), tag: logTag, metadata: metadata, file: file, function: function, line: line)
    }

    func logError(_ error: Error, metadata: LogMetadata = [:], file: String = #fileID, function: String = #function, line: Int = #line) {
        SwiftMoLogger.error(error, tag: logTag, metadata: metadata, file: file, function: function, line: line)
    }

    func logDebug(_ message: @autoclosure () -> String, metadata: LogMetadata = [:], file: String = #fileID, function: String = #function, line: Int = #line) {
        SwiftMoLogger.debug(message(), tag: logTag, metadata: metadata, file: file, function: function, line: line)
    }
}
