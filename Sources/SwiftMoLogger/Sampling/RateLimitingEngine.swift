import Foundation

/// Token-bucket rate limiter wrapping another engine.
///
/// Protects downstream sinks (file, network) from log floods during
/// cascading failures. Tokens accumulate at ``permitsPerSecond``; any entry
/// arriving with no available token is dropped silently. A separate
/// ``burst`` allows short spikes through.
///
/// The implementation uses a small critical section guarded by
/// `os_unfair_lock`; on the hot path it amounts to a comparison and a
/// subtraction.
public final class RateLimitingLogEngine: LogEngine, @unchecked Sendable {
    public let engineID: String
    public let minimumLevel: LogLevel

    private let wrapped: any LogEngine
    private let permitsPerSecond: Double
    private let burst: Double
    private let lock = UnfairLock()
    private var tokens: Double
    private var lastRefill: DispatchTime
    private var droppedSinceLast: Int = 0

    public init(wrapping wrapped: any LogEngine, permitsPerSecond: Double, burst: Double? = nil) {
        precondition(permitsPerSecond > 0)
        self.wrapped = wrapped
        self.permitsPerSecond = permitsPerSecond
        self.burst = burst ?? permitsPerSecond
        self.tokens = self.burst
        self.lastRefill = .now()
        self.engineID = "swiftmologger.ratelimit.\(wrapped.engineID)"
        self.minimumLevel = wrapped.minimumLevel
    }

    /// Forwards to the wrapped engine.
    public func flush() { wrapped.flush() }

    public func log(_ entry: LogEntry) {
        if acquire() {
            wrapped.log(entry)
        } else {
            // Don't recurse through the framework — emit a summary entry
            // once every N drops at most.
            lock.lock()
            droppedSinceLast += 1
            let snapshot = droppedSinceLast
            if snapshot.isMultiple(of: 100) {
                lock.unlock()
                NSLog("RateLimitingLogEngine dropped %d entries", snapshot)
            } else {
                lock.unlock()
            }
        }
    }

    private func acquire() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = DispatchTime.now()
        let elapsed = Double(now.uptimeNanoseconds - lastRefill.uptimeNanoseconds) / 1_000_000_000
        if elapsed > 0 {
            tokens = min(burst, tokens + elapsed * permitsPerSecond)
            lastRefill = now
        }
        if tokens >= 1 {
            tokens -= 1
            return true
        }
        return false
    }
}
