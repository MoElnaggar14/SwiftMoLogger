import Logging
import SwiftMoLogger

/// A swift-log `LogHandler` that sends every `Logger` call into SwiftMoLogger's
/// engines.
///
/// Much of the Swift ecosystem (SwiftNIO, AsyncHTTPClient, gRPC, the AWS SDK,
/// Vapor, …) logs through swift-log. Bootstrapping with this handler makes
/// those logs show up next to your own: in Console.app via the system logger,
/// in files, in the Diagnostics Hub and in any remote engine.
///
/// ```swift
/// import SwiftMoLoggerSwiftLog
///
/// // Once, at launch (your composition root):
/// SwiftMoLogHandler.bootstrap(logger: logging.logger)
///
/// // Anywhere, including inside third-party packages:
/// let logger = Logger(label: "com.example.sync")
/// logger.info("Synced", metadata: ["items": "42"])
/// ```
///
/// Each entry is tagged with the logger's label (domain `swiftlog.<label>`), so
/// the Hub and ``LogConsoleView`` can filter by library.
public struct SwiftMoLogHandler: LogHandler {
    public var logLevel: Logger.Level
    public var metadata: Logger.Metadata = [:]
    public var metadataProvider: Logger.MetadataProvider?

    public let label: String
    private let logger: MoLogger

    /// - Parameters:
    ///   - label: The swift-log label (usually reverse-DNS).
    ///   - logger: Where entries go.
    ///   - logLevel: Lowest swift-log level forwarded. Libraries are chatty at
    ///     `.trace`/`.debug`, so the swift-log convention of `.info` is the default.
    ///   - metadataProvider: Contributes metadata to every entry (swift-log 1.5+).
    public init(
        label: String,
        logger: MoLogger,
        logLevel: Logger.Level = .info,
        metadataProvider: Logger.MetadataProvider? = nil
    ) {
        self.label = label
        self.logLevel = logLevel
        self.metadataProvider = metadataProvider
        self.logger = logger.with(tag: LogTag("[\(label)]", domain: "swiftlog.\(label)"))
    }

    /// Installs this handler as the process-wide swift-log backend.
    ///
    /// swift-log only allows bootstrapping once per process (it traps on a
    /// second call), so call this exactly once, early in launch. This is
    /// swift-log's own process-wide hook; SwiftMoLogger itself keeps no
    /// global state.
    public static func bootstrap(
        logger: MoLogger,
        logLevel: Logger.Level = .info,
        metadataProvider: Logger.MetadataProvider? = nil
    ) {
        LoggingSystem.bootstrap({ label, provider in
            SwiftMoLogHandler(
                label: label,
                logger: logger,
                logLevel: logLevel,
                metadataProvider: provider ?? metadataProvider
            )
        }, metadataProvider: metadataProvider)
    }

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    public func log(event: LogEvent) {
        // Precedence, lowest to highest: handler metadata, provider, call site.
        var merged = metadata
        if let provided = metadataProvider?.get() {
            merged.merge(provided) { _, new in new }
        }
        if let explicit = event.metadata {
            merged.merge(explicit) { _, new in new }
        }
        var converted = LogMetadata(merged.mapValues(LogMetadataValue.init(swiftLog:)))
        converted["logger.source"] = .string(event.source)
        if let error = event.error {
            converted["error_type"] = .string(String(describing: type(of: error)))
            converted["error"] = .string(String(describing: error))
        }

        // swift-log flattens the message before it gets here and has its own
        // privacy rules, so it's passed through verbatim (public).
        logger.log(
            LogLevel(swiftLog: event.level),
            LogMessage(verbatim: event.message.description),
            metadata: converted,
            file: event.file,
            function: event.function,
            line: Int(event.line),
            column: 0
        )
    }
}

// MARK: - Mapping

public extension LogLevel {
    /// The SwiftMoLogger level for a swift-log level. swift-log has no `fault`.
    init(swiftLog level: Logger.Level) {
        switch level {
        case .trace: self = .trace
        case .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warning: self = .warning
        case .error: self = .error
        case .critical: self = .critical
        }
    }
}

public extension LogMetadataValue {
    /// Converts swift-log metadata, keeping its structure.
    init(swiftLog value: Logger.Metadata.Value) {
        switch value {
        case let .string(string):
            self = .string(string)
        case let .stringConvertible(convertible):
            self = .string(convertible.description)
        case let .array(values):
            self = .array(values.map(LogMetadataValue.init(swiftLog:)))
        case let .dictionary(dictionary):
            self = .dictionary(dictionary.mapValues(LogMetadataValue.init(swiftLog:)))
        }
    }
}
