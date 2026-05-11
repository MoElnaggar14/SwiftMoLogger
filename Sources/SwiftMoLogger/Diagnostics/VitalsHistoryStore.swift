import Foundation

/// One vitals tick — kept duplicate-free from the diagnostics target so
/// stores can live in the core module without importing the diagnostics
/// module.
public struct VitalsTick: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let memoryMB: Double
    public let cpuPercent: Double
    public let fps: Double
    public let thermalState: String
    public let batteryLevel: Double

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        memoryMB: Double,
        cpuPercent: Double,
        fps: Double,
        thermalState: String,
        batteryLevel: Double
    ) {
        self.id = id
        self.timestamp = timestamp
        self.memoryMB = memoryMB
        self.cpuPercent = cpuPercent
        self.fps = fps
        self.thermalState = thermalState
        self.batteryLevel = batteryLevel
    }
}

/// Rolling vitals history for the Diagnostics Hub charts.
public final class VitalsHistoryStore: @unchecked Sendable {
    public static let shared = VitalsHistoryStore()

    public let capacity: Int
    private var buffer: [VitalsTick?]
    private var head = 0
    private var count = 0
    private var lock = os_unfair_lock_s()

    public init(capacity: Int = 600) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.buffer = Array(repeating: nil, count: capacity)
    }

    public func record(_ tick: VitalsTick) {
        os_unfair_lock_lock(&lock)
        buffer[head] = tick
        head = (head + 1) % capacity
        if count < capacity { count += 1 }
        os_unfair_lock_unlock(&lock)
    }

    public func snapshot() -> [VitalsTick] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        guard count > 0 else { return [] }
        var out: [VitalsTick] = []
        out.reserveCapacity(count)
        let start = count == capacity ? head : 0
        for offset in 0..<count {
            if let tick = buffer[(start + offset) % capacity] {
                out.append(tick)
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
