import Foundation

/// The level methods. Each takes a ``LogMessage``, so a string literal's text is
/// public and its interpolated values are private unless marked or declared safe:
///
/// ```swift
/// log.info("Signed in \(email)")                       // "Signed in <private>"
/// log.info("Opened \(screen, privacy: .public)")       // "Opened Settings"
/// log.info("Retry \(attempt) of \(limit)")              // "Retry 2 of 5"
/// log.info(LogMessage(verbatim: text))                 // a String you know is safe
/// ```
public extension MoLogger {
    /// Logs a ``LogMessage`` at `level`. The message is an autoclosure: it is
    /// built only when the entry passes the registry's filter, and its hidden
    /// values are replaced before the ``LogEntry`` is created, so no engine sees
    /// them.
    func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        let resolvedTag = tag ?? self.tag
        guard registry.accepts(level, tag: resolvedTag) else { return }
        let built = message()
        let text = built.rendered(revealingPrivateValues: built.hasPrivateValues && registry.revealsPrivateValues)
        registry.dispatch(LogEntry(
            level: level,
            message: text,
            tag: resolvedTag,
            metadata: self.metadata.isEmpty ? metadata : self.metadata.merging(metadata),
            source: SourceLocation(file: file, function: function, line: line, column: column)
        ))
    }

    func trace(
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        log(
            .trace,
            message(),
            tag: tag,
            metadata: metadata,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }

    /// Debug-only: compiled out of release builds, so the message is never evaluated there.
    func debug(
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        #if DEBUG
        log(
            .debug,
            message(),
            tag: tag,
            metadata: metadata,
            file: file,
            function: function,
            line: line,
            column: column
        )
        #endif
    }

    func info(
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        log(
            .info,
            message(),
            tag: tag,
            metadata: metadata,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }

    func notice(
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        log(
            .notice,
            message(),
            tag: tag,
            metadata: metadata,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }

    func warning(
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        log(
            .warning,
            message(),
            tag: tag,
            metadata: metadata,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }

    func error(
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        log(
            .error,
            message(),
            tag: tag,
            metadata: metadata,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }

    func critical(
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        log(
            .critical,
            message(),
            tag: tag,
            metadata: metadata,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }

    func fault(
        _ message: @autoclosure () -> LogMessage,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        log(
            .fault,
            message(),
            tag: tag,
            metadata: metadata,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }
}
