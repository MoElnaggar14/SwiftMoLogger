import Foundation

/// `LogMessage` overloads of the level methods, for per-value privacy:
///
/// ```swift
/// log.info("Signed in \(email, privacy: .private)")   // "Signed in <private>"
/// ```
///
/// They sit alongside the `String` overloads and are marked
/// `@_disfavoredOverload`, so any call that type-checks against `String` keeps
/// using it (including expressions whose type comes from context, such as
/// `log.info({ … }())`). Only a literal that uses `privacy:`, or a `LogMessage`
/// value, resolves here.
public extension MoLogger {
    /// Logs a ``LogMessage``. Like the `String` overload, the message is built
    /// only when the entry passes the registry's filter; its hidden values are
    /// replaced before the ``LogEntry`` is created.
    @_disfavoredOverload
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

    @_disfavoredOverload
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
    @_disfavoredOverload
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

    @_disfavoredOverload
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

    @_disfavoredOverload
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

    @_disfavoredOverload
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

    @_disfavoredOverload
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

    @_disfavoredOverload
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

    @_disfavoredOverload
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
