import Foundation

/// Process-wide broadcast of `LogEntry` values as an `AsyncSequence`.
///
/// Internally backed by `AsyncStream` continuations stored per subscriber.
/// New entries are fanned out to every active subscriber without blocking the
/// caller; back-pressure is bounded by per-subscriber buffer policy.
///
/// ```swift
/// let stream = LogStream.shared.subscribe(bufferSize: 256)
/// for await entry in stream where entry.level >= .warning {
///     await reportToBackend(entry)
/// }
/// ```
public final class LogStream: LogEngine, @unchecked Sendable {
    public static let shared = LogStream()

    public let engineID: String = "swiftmologger.stream"
    public let minimumLevel: LogLevel = .trace

    private var continuations: [UUID: AsyncStream<LogEntry>.Continuation] = [:]
    private var lock = os_unfair_lock_s()

    public init() {}

    public func log(_ entry: LogEntry) {
        os_unfair_lock_lock(&lock)
        let snapshot = Array(continuations.values)
        os_unfair_lock_unlock(&lock)
        for continuation in snapshot {
            continuation.yield(entry)
        }
    }

    /// Subscribe to the live entry stream. Returns an `AsyncStream` that the
    /// caller should iterate; cancellation tears down the subscription
    /// automatically.
    ///
    /// - Parameter bufferSize: Maximum entries buffered before the policy
    ///   kicks in. Older entries are dropped on overflow so a slow consumer
    ///   can never stall producers.
    public func subscribe(bufferSize: Int = 256) -> AsyncStream<LogEntry> {
        AsyncStream(LogEntry.self, bufferingPolicy: .bufferingNewest(bufferSize)) { continuation in
            let id = UUID()
            os_unfair_lock_lock(&lock)
            continuations[id] = continuation
            os_unfair_lock_unlock(&lock)

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                os_unfair_lock_lock(&self.lock)
                self.continuations.removeValue(forKey: id)
                os_unfair_lock_unlock(&self.lock)
            }
        }
    }

    /// Number of currently active subscribers. Exposed for tests/diagnostics.
    public var subscriberCount: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return continuations.count
    }
}
