import Foundation

/// Decorator engine that runs every entry through a ``Redactor`` before
/// forwarding to the wrapped engine.
///
/// Two recommended placements:
/// 1. **Process-wide redaction.** Replace the default `SystemLogger` with
///    `RedactingLogEngine(wrapping: SystemLogger())` so nothing — console,
///    file, network — sees raw PII.
/// 2. **Selective redaction.** Wrap only the network/file sinks; keep the
///    `MemoryLogEngine` raw for in-app debugging.
public final class RedactingLogEngine: LogEngine, @unchecked Sendable {
    public let engineID: String
    public let minimumLevel: LogLevel

    private let wrapped: any LogEngine
    private let redactor: Redactor

    public init(wrapping wrapped: any LogEngine, redactor: Redactor = Redactor()) {
        self.wrapped = wrapped
        self.redactor = redactor
        self.engineID = "swiftmologger.redacting.\(wrapped.engineID)"
        self.minimumLevel = wrapped.minimumLevel
    }

    public func log(_ entry: LogEntry) {
        let (redactedMessage, _) = redactor.redact(entry.message)
        let redactedMetadata = redactor.redact(entry.metadata)
        let redacted = LogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level,
            message: redactedMessage,
            tag: entry.tag,
            metadata: redactedMetadata,
            source: entry.source,
            threadName: entry.threadName
        )
        wrapped.log(redacted)
    }
}

public extension SwiftMoLogger {
    /// Install global redaction by replacing the engine at `index` with a
    /// ``RedactingLogEngine`` wrapper. Idempotent: re-running it on an
    /// already-redacted engine is a no-op.
    static func enableRedaction(at index: Int = 0, redactor: Redactor = Redactor()) {
        let engines = EngineRegistry.shared.allEngines()
        guard engines.indices.contains(index) else { return }
        let target = engines[index]
        if target is RedactingLogEngine { return }
        let wrapped = RedactingLogEngine(wrapping: target, redactor: redactor)
        EngineRegistry.shared.removeAllEngines()
        for (offset, engine) in engines.enumerated() {
            EngineRegistry.shared.addEngine(offset == index ? wrapped : engine)
        }
    }
}
