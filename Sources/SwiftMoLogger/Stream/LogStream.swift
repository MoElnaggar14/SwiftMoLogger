import Foundation

/// Broadcasts the entries of the registry it's added to as an `AsyncSequence`.
/// ``LogEnvironment`` creates and registers one for you.
///
/// Internally backed by `AsyncStream` continuations stored per subscriber.
/// New entries are fanned out to every active subscriber without blocking the
/// caller; back-pressure is bounded by per-subscriber buffer policy.
///
/// ```swift
/// let stream = environment.stream.subscribe(bufferSize: 256)
/// for await entry in stream where entry.level >= .warning {
///     await reportToBackend(entry)
/// }
/// ```
public final class LogStream: LogEngine, @unchecked Sendable {
    public let engineID = "swiftmologger.stream.\(UUID().uuidString)"
    public let minimumLevel: LogLevel = .trace

    private var continuations: [UUID: AsyncStream<LogEntry>.Continuation] = [:]
    private let lock = UnfairLock()

    public init() {}

    public func log(_ entry: LogEntry) {
        lock.lock()
        let snapshot = Array(continuations.values)
        lock.unlock()
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
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self = self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    /// Number of currently active subscribers. Exposed for tests/diagnostics.
    public var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }
}
