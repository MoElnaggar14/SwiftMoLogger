import Foundation

/// A MetricKit payload in its JSON form, as `jsonRepresentation()` returns it.
///
/// Payloads travel as JSON rather than as `MXMetricPayload` / `MXDiagnosticPayload`
/// objects so they can be recorded, replayed in tests, and produced by sources
/// other than `MXMetricManager`.
public struct MetricKitPayload: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        /// A daily metric payload (`MXMetricPayload`): launch times, hangs, memory, disk, CPU.
        case metrics
        /// A diagnostic payload (`MXDiagnosticPayload`): crashes, hangs, CPU and disk-write exceptions.
        case diagnostics
    }

    public let kind: Kind
    public let json: Data

    public init(kind: Kind, json: Data) {
        self.kind = kind
        self.json = json
    }
}

/// The port ``MetricKitCrashReporter`` reads payloads from.
///
/// `MXMetricManagerPayloadSource` (iOS and macOS) is the implementation that
/// subscribes to `MXMetricManager`. A newer system API, a replay of recorded
/// payloads, or a test double can be plugged in by conforming to this protocol
/// and passing it to ``MetricKitCrashReporter/init(logger:source:)``.
public protocol MetricPayloadSource: AnyObject {
    /// Starts delivering payloads to `handler`, on any thread.
    func start(delivering handler: @escaping @Sendable ([MetricKitPayload]) -> Void)
    /// Stops delivering payloads. The source drops its handler.
    func stop()
}
