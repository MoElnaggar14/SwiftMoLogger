import Foundation

/// A finished signpost span, recorded by ``Signposter``.
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
    public let capacity: Int
    private var buffer: [SignpostEvent?]
    private var head = 0
    private var count = 0
    private let lock = UnfairLock()

    public init(capacity: Int = 500) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    public func record(_ event: SignpostEvent) {
        lock.lock()
        buffer[head] = event
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
        lock.unlock()
    }

    public func snapshot() -> [SignpostEvent] {
        lock.lock()
        defer { lock.unlock() }
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
        lock.lock()
        for index in 0..<capacity { buffer[index] = nil }
        head = 0; count = 0
        lock.unlock()
    }
}
