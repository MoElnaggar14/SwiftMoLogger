import Foundation

/// W3C Trace Context — `traceparent` header value.
///
/// Format: `00-<32 hex traceID>-<16 hex spanID>-<2 hex flags>`
///
/// Lets you tie an iOS-side operation to the downstream backend trace in
/// any W3C-compliant APM (Datadog, Honeycomb, New Relic, OpenTelemetry).
public struct TraceContext: Sendable, Hashable, Codable, CustomStringConvertible {
    public let traceID: String   // 32 lowercase hex chars
    public let spanID: String    // 16 lowercase hex chars
    public let sampled: Bool

    public init(traceID: String, spanID: String, sampled: Bool = true) {
        precondition(traceID.count == 32, "traceID must be 32 hex chars")
        precondition(spanID.count == 16, "spanID must be 16 hex chars")
        self.traceID = traceID
        self.spanID = spanID
        self.sampled = sampled
    }

    /// Generate a fresh root context.
    public static func generate(sampled: Bool = true) -> TraceContext {
        TraceContext(
            traceID: randomHex(byteCount: 16),
            spanID: randomHex(byteCount: 8),
            sampled: sampled
        )
    }

    /// Spawn a child span sharing this trace.
    public func childSpan() -> TraceContext {
        TraceContext(
            traceID: traceID,
            spanID: TraceContext.randomHex(byteCount: 8),
            sampled: sampled
        )
    }

    /// Parse a `traceparent` header value. Returns `nil` for malformed input.
    public static func parse(traceparent: String) -> TraceContext? {
        let parts = traceparent.split(separator: "-")
        guard parts.count == 4 else { return nil }
        guard parts[0] == "00" else { return nil }
        let traceID = String(parts[1])
        let spanID = String(parts[2])
        guard traceID.count == 32, spanID.count == 16 else { return nil }
        let flagsValue = UInt8(parts[3], radix: 16) ?? 0
        return TraceContext(traceID: traceID, spanID: spanID, sampled: (flagsValue & 0x01) != 0)
    }

    /// Render as `traceparent` header value.
    public var traceparent: String {
        let flags = sampled ? "01" : "00"
        return "00-\(traceID)-\(spanID)-\(flags)"
    }

    public var description: String { traceparent }

    /// Metadata bag suitable for attachment to a `LogEntry`.
    public var metadata: LogMetadata {
        [
            "trace.id": .string(traceID),
            "span.id": .string(spanID),
            "trace.sampled": .bool(sampled)
        ]
    }

    private static func randomHex(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        _ = bytes.withUnsafeMutableBufferPointer { ptr in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, ptr.baseAddress!)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Task-local current trace context. Network layers and engines read this
/// to inject `traceparent` headers and stamp log entries.
public enum CurrentTrace {
    @TaskLocal
    public static var current: TraceContext?
}

public extension SwiftMoLogger {
    /// Run `block` inside a fresh trace. Any log entries emitted during the
    /// block automatically carry the `trace.id` / `span.id` metadata, and
    /// any `URLSession` request flowing through ``SwiftMoLoggerNetwork``
    /// will get the `traceparent` header injected.
    static func withTrace<T>(
        _ context: TraceContext = .generate(),
        _ block: () throws -> T
    ) rethrows -> T {
        try CurrentTrace.$current.withValue(context) {
            try withContext(context.metadata, block)
        }
    }

    static func withTrace<T>(
        _ context: TraceContext = .generate(),
        _ block: () async throws -> T
    ) async rethrows -> T {
        try await CurrentTrace.$current.withValue(context) {
            try await withContext(context.metadata, block)
        }
    }
}
