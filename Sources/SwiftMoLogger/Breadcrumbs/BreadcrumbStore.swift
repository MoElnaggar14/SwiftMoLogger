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
    public static let shared = BreadcrumbStore()

    private var buffer: [Breadcrumb?]
    private var head: Int = 0
    private var count: Int = 0
    private var lock = os_unfair_lock_s()
    public let capacity: Int

    public init(capacity: Int = 100) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    public func record(_ crumb: Breadcrumb) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        buffer[head] = crumb
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
    }

    public func snapshot() -> [Breadcrumb] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
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
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        for index in 0..<capacity { buffer[index] = nil }
        head = 0
        count = 0
    }
}

public extension SwiftMoLogger {
    /// Record a breadcrumb. Cheap: O(1) append into a fixed-capacity buffer.
    static func breadcrumb(
        _ message: String,
        category: Breadcrumb.Category = .custom,
        metadata: LogMetadata = [:]
    ) {
        BreadcrumbStore.shared.record(
            Breadcrumb(category: category, message: message, metadata: metadata)
        )
    }

    /// Snapshot of recent breadcrumbs, oldest first. Use this when bundling
    /// a crash report or bug report.
    static func breadcrumbs() -> [Breadcrumb] {
        BreadcrumbStore.shared.snapshot()
    }

    /// Reset the global breadcrumb store. Typically called after a session
    /// boundary (user logged out, app foregrounded after a long background).
    static func clearBreadcrumbs() {
        BreadcrumbStore.shared.clear()
    }
}
