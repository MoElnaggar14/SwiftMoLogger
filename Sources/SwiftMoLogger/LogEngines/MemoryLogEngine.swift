import Foundation

/// Bounded in-memory ring buffer of recent log entries.
///
/// Useful for crash-bundling (attach the last N log lines to a bug report),
/// for in-app log viewers, and for tests that want to assert on emitted log
/// entries.
///
/// Implementation is a fixed-capacity circular buffer guarded by an unfair
/// lock — O(1) append, O(N) snapshot. The buffer never reallocates after
/// construction, so logging in tight loops does not produce GC churn.
public final class MemoryLogEngine: LogEngine, @unchecked Sendable {
    /// Unique per instance unless you pass an `id`, so two memory engines
    /// (yours, the Flight Recorder's, the Diagnostics Hub's) never replace
    /// each other in the registry.
    public let engineID: String
    public let minimumLevel: LogLevel

    private let capacity: Int
    private var buffer: [LogEntry?]
    private var head: Int = 0
    private var count: Int = 0
    private let lock = UnfairLock()
    private var errorCount: Int = 0
    private var warningCount: Int = 0

    public init(capacity: Int = 1_000, minimumLevel: LogLevel = .trace, id: String? = nil) {
        precondition(capacity > 0, "MemoryLogEngine capacity must be positive")
        self.engineID = id ?? "swiftmologger.memory.\(UUID().uuidString)"
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
        self.minimumLevel = minimumLevel
    }

    public func log(_ entry: LogEntry) {
        lock.lock()
        buffer[head] = entry
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
        switch entry.level {
        case .error, .critical, .fault: errorCount += 1
        case .warning: warningCount += 1
        default: break
        }
        lock.unlock()
    }

    /// Snapshot of all retained entries in insertion order (oldest first).
    public func snapshot() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return [] }
        var result: [LogEntry] = []
        result.reserveCapacity(count)
        let start = count == capacity ? head : 0
        for offset in 0..<count {
            let index = (start + offset) % capacity
            if let entry = buffer[index] {
                result.append(entry)
            }
        }
        return result
    }

    /// Return the most recent `n` entries (oldest first).
    public func recent(_ requested: Int) -> [LogEntry] {
        let all = snapshot()
        guard requested < all.count else { return all }
        return Array(all.suffix(requested))
    }

    /// Filter snapshot by level / tag domain / substring without re-acquiring
    /// the lock per predicate.
    public func filtered(
        minLevel: LogLevel? = nil,
        domain: String? = nil,
        contains substring: String? = nil
    ) -> [LogEntry] {
        snapshot().filter { entry in
            if let minLevel = minLevel, entry.level < minLevel { return false }
            if let domain = domain, entry.tag?.domain != domain { return false }
            if let substring = substring, !entry.message.contains(substring) { return false }
            return true
        }
    }

    /// Aggregate counters maintained at insertion time — O(1) read.
    public func counters() -> (total: Int, warnings: Int, errors: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (count, warningCount, errorCount)
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<capacity { buffer[index] = nil }
        head = 0
        count = 0
        errorCount = 0
        warningCount = 0
    }
}
