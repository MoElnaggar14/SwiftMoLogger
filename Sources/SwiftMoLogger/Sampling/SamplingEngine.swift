import Foundation

/// Decorator engine that probabilistically drops entries before forwarding.
///
/// Two strategies:
/// - **Uniform sampling**: each entry survives with probability ``rate``.
/// - **Per-level sampling**: caller supplies a `[LogLevel: Double]`. Levels
///   not present in the table always pass through.
///
/// Decisions use a thread-local PRNG so sampling does not contend on a
/// global lock on the hot path.
public final class SamplingLogEngine: LogEngine, @unchecked Sendable {
    public enum Strategy: Sendable {
        case uniform(rate: Double)
        case perLevel(rates: [LogLevel: Double])
    }

    public let engineID: String
    public let minimumLevel: LogLevel

    private let wrapped: any LogEngine
    private let strategy: Strategy

    public init(wrapping wrapped: any LogEngine, strategy: Strategy) {
        self.wrapped = wrapped
        self.strategy = strategy
        self.engineID = "swiftmologger.sampling.\(wrapped.engineID)"
        self.minimumLevel = wrapped.minimumLevel
    }

    public func log(_ entry: LogEntry) {
        if shouldKeep(entry) {
            wrapped.log(entry)
        }
    }

    private func shouldKeep(_ entry: LogEntry) -> Bool {
        let rate: Double
        switch strategy {
        case .uniform(let value):
            rate = value
        case .perLevel(let rates):
            rate = rates[entry.level] ?? 1.0
        }
        if rate >= 1.0 { return true }
        if rate <= 0.0 { return false }
        return Double.random(in: 0..<1) < rate
    }
}
