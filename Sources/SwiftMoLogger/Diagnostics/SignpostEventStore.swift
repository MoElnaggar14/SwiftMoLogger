import Foundation

/// A finished signpost span, captured by ``LogSignpost``.
public struct SignpostEvent: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let name: String
    public let startedAt: Date
    public let endedAt: Date
    public let tagDomain: String?
    public let depth: Int

    public var durationSeconds: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    public init(id: UUID = UUID(), name: String, startedAt: Date, endedAt: Date, tagDomain: String? = nil, depth: Int = 0) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.tagDomain = tagDomain
        self.depth = depth
    }
}

/// Bounded ring buffer of finished signpost spans.
public final class SignpostEventStore: @unchecked Sendable {
    public static let shared = SignpostEventStore()

    public let capacity: Int
    private var buffer: [SignpostEvent?]
    private var head = 0
    private var count = 0
    private var lock = os_unfair_lock_s()

    public init(capacity: Int = 500) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    public func record(_ event: SignpostEvent) {
        os_unfair_lock_lock(&lock)
        buffer[head] = event
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
        os_unfair_lock_unlock(&lock)
    }

    public func snapshot() -> [SignpostEvent] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard count > 0 else { return [] }
        var out: [SignpostEvent] = []
        out.reserveCapacity(count)
        let start = count == capacity ? head : 0
        for offset in 0..<count {
            if let event = buffer[(start + offset) % capacity] {
                out.append(event)
            }
        }
        return out
    }

    public func clear() {
        os_unfair_lock_lock(&lock)
        for index in 0..<capacity { buffer[index] = nil }
        head = 0; count = 0
        os_unfair_lock_unlock(&lock)
    }
}
