import Foundation

/// Bounded, thread-safe store of recent ``Breadcrumb``s.
///
/// Capacity-limited (default 100) so an active session can drop hundreds of
/// navigation/UI breadcrumbs without unbounded memory growth. Snapshots are
/// `Sendable` value arrays — safe to ship into a crash report from any
/// thread, including a signal-handler context where heap allocation should
/// be avoided (use ``snapshot()`` on the main thread before the signal
/// fires, or rely on ``MetricKitCrashReporter`` which is invoked
/// out-of-process).
public final class BreadcrumbStore: @unchecked Sendable {
    private var buffer: [Breadcrumb?]
    private var head: Int = 0
    private var count: Int = 0
    private let lock = UnfairLock()
    public let capacity: Int

    public init(capacity: Int = 100) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    public func record(_ crumb: Breadcrumb) {
        lock.lock()
        defer { lock.unlock() }
        buffer[head] = crumb
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    public func snapshot() -> [Breadcrumb] {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return [] }
        var out: [Breadcrumb] = []
        out.reserveCapacity(count)
        let start = count == capacity ? head : 0
        for offset in 0..<count {
            let index = (start + offset) % capacity
            if let crumb = buffer[index] {
                out.append(crumb)
            }
        }
        return out
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        for index in 0..<capacity { buffer[index] = nil }
        head = 0
        count = 0
    }
}

public extension BreadcrumbStore {
    /// Record a breadcrumb. Cheap: O(1) append into a fixed-capacity buffer.
    func record(
        _ message: String,
        category: Breadcrumb.Category = .custom,
        metadata: LogMetadata = [:]
    ) {
        record(Breadcrumb(category: category, message: message, metadata: metadata))
    }
}
