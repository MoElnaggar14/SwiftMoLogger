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

    // MARK: Errors

    /// Logs `error` at ``LogLevel/error``. The message is the error's
    /// `localizedDescription`, private like any interpolated value, so it shows as
    /// `<private>` unless private values are revealed. The `error_type` metadata
    /// (the type's name) stays public, so entries can still be grouped. The `error`
    /// metadata holds `String(describing: error)`: privacy covers the message, not
    /// metadata, which ``RedactingLogEngine`` handles.
    ///
    /// To show the description, log it yourself:
    /// `log.error("\(error.localizedDescription, privacy: .public)")`.
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
            "\(error.localizedDescription)",
            tag: tag,
            metadata: enriched,
            file: file,
            function: function,
            line: line,
            column: column
        )
    }
}
