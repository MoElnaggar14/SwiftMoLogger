import XCTest
@testable import SwiftMoLogger

final class SamplingTests: XCTestCase {

    func testUniformSamplingRespectsRate() {
        let memory = MemoryLogEngine(capacity: 10_000)
        let sampling = SamplingLogEngine(wrapping: memory, strategy: .uniform(rate: 0.1))
        for index in 0..<5_000 {
            sampling.log(LogEntry(level: .info, message: "msg-\(index)"))
        }
        let kept = memory.counters().total
        XCTAssertGreaterThan(kept, 250)
        XCTAssertLessThan(kept, 1_000)
    }

    func testRateZeroDropsAll() {
        let memory = MemoryLogEngine(capacity: 1_000)
        let sampling = SamplingLogEngine(wrapping: memory, strategy: .uniform(rate: 0))
        for index in 0..<100 {
            sampling.log(LogEntry(level: .info, message: "m\(index)"))
        }
        XCTAssertEqual(memory.counters().total, 0)
    }

    func testRateOneKeepsAll() {
        let memory = MemoryLogEngine(capacity: 1_000)
        let sampling = SamplingLogEngine(wrapping: memory, strategy: .uniform(rate: 1))
        for index in 0..<100 {
            sampling.log(LogEntry(level: .info, message: "m\(index)"))
        }
        XCTAssertEqual(memory.counters().total, 100)
    }

    func testPerLevelKeepsCriticalEvenIfTraceSampled() {
        let memory = MemoryLogEngine(capacity: 1_000)
        let sampling = SamplingLogEngine(wrapping: memory, strategy: .perLevel(rates: [.trace: 0, .info: 0]))
        sampling.log(LogEntry(level: .trace, message: "dropped"))
        sampling.log(LogEntry(level: .info, message: "dropped"))
        sampling.log(LogEntry(level: .error, message: "kept"))
        XCTAssertEqual(memory.counters().total, 1)
        XCTAssertEqual(memory.snapshot().first?.message, "kept")
    }

    func testRateLimiterBlocksExcessAfterBurst() {
        let memory = MemoryLogEngine(capacity: 1_000)
        let limited = RateLimitingLogEngine(wrapping: memory, permitsPerSecond: 10, burst: 5)
        for index in 0..<50 {
            limited.log(LogEntry(level: .info, message: "m\(index)"))
        }
        let kept = memory.counters().total
        XCTAssertGreaterThanOrEqual(kept, 5)
        XCTAssertLessThan(kept, 50)
    }
}
