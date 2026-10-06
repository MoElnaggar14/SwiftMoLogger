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

    /// A context from IDs you received (for example from a backend header).
    /// Returns `nil` unless `traceID` is 32 and `spanID` 16 hex characters, and
    /// neither is all zeros (W3C treats those as invalid).
    public init?(traceID: String, spanID: String, sampled: Bool = true) {
        guard Self.isValidID(traceID, length: 32), Self.isValidID(spanID, length: 16) else { return nil }
        self.init(validTraceID: traceID.lowercased(), spanID: spanID.lowercased(), sampled: sampled)
    }

    private init(validTraceID traceID: String, spanID: String, sampled: Bool) {
        self.traceID = traceID
        self.spanID = spanID
        self.sampled = sampled
    }

    private static func isValidID(_ id: String, length: Int) -> Bool {
        id.utf8.count == length
            && id.allSatisfy(\.isHexDigit)
            && id.contains { $0 != "0" }
    }

    /// Generate a fresh root context.
    public static func generate(sampled: Bool = true) -> TraceContext {
        TraceContext(
            validTraceID: randomHex(byteCount: 16),
            spanID: randomHex(byteCount: 8),
            sampled: sampled
        )
    }

    /// Spawn a child span sharing this trace.
    public func childSpan() -> TraceContext {
        TraceContext(
            validTraceID: traceID,
            spanID: TraceContext.randomHex(byteCount: 8),
            sampled: sampled
        )
    }

    /// Parse a `traceparent` header value. Returns `nil` for malformed input.
    public static func parse(traceparent: String) -> TraceContext? {
        let parts = traceparent.split(separator: "-")
        guard parts.count == 4 else { return nil }
        guard parts[0] == "00" else { return nil }
        let flagsValue = UInt8(parts[3], radix: 16) ?? 0
        return TraceContext(traceID: String(parts[1]), spanID: String(parts[2]), sampled: (flagsValue & 0x01) != 0)
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

public extension TraceContext {
    /// Runs `operation` inside this trace. Entries logged inside carry the
    /// `trace.id` / `span.id` metadata, and ``CurrentTrace/current`` is set so
    /// network layers can send a `traceparent` header.
    ///
    /// ```swift
    /// try await TraceContext.generate().run {
    ///     try await api.checkout()
    /// }
    /// ```
    func run<T>(_ operation: () throws -> T) rethrows -> T {
        try CurrentTrace.$current.withValue(self) {
            try LogContext.with(metadata, operation: operation)
        }
    }

    #if compiler(>=6.4)
    /// Async variant; runs on the caller's executor, like ``LogContext/with(_:operation:)``.
    nonisolated(nonsending) func run<T>(
        _ operation: nonisolated(nonsending) () async throws -> T
    ) async rethrows -> T {
        try await CurrentTrace.$current.withValue(self) {
            try await LogContext.with(metadata, operation: operation)
        }
    }
    #else
    func run<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await CurrentTrace.$current.withValue(self) {
            try await LogContext.with(metadata, operation: operation)
        }
    }
    #endif
}
