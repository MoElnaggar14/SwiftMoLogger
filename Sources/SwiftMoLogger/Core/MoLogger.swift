import Foundation

/// An injectable logger: an ``EngineRegistry`` plus a default tag and bound
/// metadata.
///
/// There is no global logger. Build a ``LogEnvironment`` at your composition
/// root and inject `environment.logger` (or a child of it) into each component:
///
/// ```swift
/// final class CheckoutService {
///     private let log: MoLogger
///
///     init(log: MoLogger) {
///         self.log = log.with(tag: .business).with(metadata: ["component": "checkout"])
///     }
///
///     func pay(orderID: String) {
///         log.info("Paying", metadata: ["order_id": .string(orderID)])
///     }
/// }
/// ```
///
/// Each logger points at the registry it was given, so a framework can keep its
/// logs separate from the host app's, and tests can run in parallel with
/// isolated registries.
public struct MoLogger: Sendable {
    public let registry: EngineRegistry
    /// Tag applied to entries that don't pass one explicitly.
    public var tag: LogTag?
    /// Metadata merged under each entry's own metadata (entry keys win).
    public var metadata: LogMetadata

    public init(registry: EngineRegistry, tag: LogTag? = nil, metadata: LogMetadata = [:]) {
        self.registry = registry
        self.tag = tag
        self.metadata = metadata
    }

    // MARK: Child loggers

    /// A copy that tags entries with `tag` by default.
    public func with(tag: LogTag?) -> MoLogger {
        var copy = self
        copy.tag = tag
        return copy
    }

    /// A copy with `metadata` merged onto this logger's metadata.
    public func with(metadata: LogMetadata) -> MoLogger {
        var copy = self
        copy.metadata = self.metadata.merging(metadata)
        return copy
    }

    // MARK: Logging

    public func log(
        _ level: LogLevel,
        _ message: @autoclosure () -> String,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        let resolvedTag = tag ?? self.tag
        guard registry.accepts(level, tag: resolvedTag) else { return }
        registry.dispatch(LogEntry(
            level: level,
            message: message(),
            tag: resolvedTag,
            metadata: self.metadata.isEmpty ? metadata : self.metadata.merging(metadata),
            source: SourceLocation(file: file, function: function, line: line, column: column)
        ))
    }

    public func trace(
        _ message: @autoclosure () -> String,
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

    /// Debug-only: the call is compiled out of release builds, so the message
    /// is never evaluated there.
    public func debug(
        _ message: @autoclosure () -> String,
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

    public func info(
        _ message: @autoclosure () -> String,
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

    public func notice(
        _ message: @autoclosure () -> String,
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

    public func warning(
        _ message: @autoclosure () -> String,
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

    public func error(
        _ message: @autoclosure () -> String,
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

    /// Logs `error`'s localized description, with `error_type` and `error` metadata.
    public func error(
        _ error: any Error,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) {
        var enriched = metadata
        enriched["error_type"] = .string(String(describing: type(of: error)))
        enriched["error"] = .string(String(describing: error))
        log(
            .error,
            error.localizedDescription,
            tag: tag,
            metadata: enriched,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }

    public func critical(
        _ message: @autoclosure () -> String,
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

    public func fault(
        _ message: @autoclosure () -> String,
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
