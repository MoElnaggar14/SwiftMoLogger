import Foundation

/// Captured snapshot of an HTTP exchange, recorded by `NetworkLogger`
/// (SwiftMoLoggerNetwork) for the Diagnostics Hub's waterfall.
public struct NetworkEvent: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date
    public let method: String
    public let url: URL
    public let statusCode: Int
    public let responseBytes: Int64
    public let requestBytes: Int64
    public let errorDescription: String?

    public var durationSeconds: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }

    public init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        method: String,
        url: URL,
        statusCode: Int,
        responseBytes: Int64,
        requestBytes: Int64,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.responseBytes = responseBytes
        self.requestBytes = requestBytes
        self.errorDescription = errorDescription
    }
}

/// Bounded ring-buffer of recent ``NetworkEvent``s.
public final class NetworkEventStore: @unchecked Sendable {
    public let capacity: Int
    private var buffer: [NetworkEvent?]
    private var head = 0
    private var count = 0
    private let lock = UnfairLock()

    public init(capacity: Int = 500) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    public func record(_ event: NetworkEvent) {
        lock.lock()
        buffer[head] = event
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
        lock.unlock()
    }

    public func snapshot() -> [NetworkEvent] {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return [] }
        var out: [NetworkEvent] = []
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
