import XCTest
@testable import SwiftMoLogger

/// Performance baselines. Numbers documented in `PERFORMANCE.md` are
/// regenerated from these tests; treat regressions in CI as a hard failure
/// once the baseline is checked in via XCTest performance metrics.
final class PerformanceBenchmarks: XCTestCase {

    override func setUp() {
        super.setUp()
        SwiftMoLogger.reset()
        SwiftMoLogger.removeEngine(at: 0)
        SwiftMoLogger.minimumLevel = .info
    }

    /// Lower bound: pure dispatch cost with no engines attached.
    func testHotPathWithNoEngines() {
        EngineRegistry.shared.removeAllEngines()
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                SwiftMoLogger.info("hot-path-\(index)")
            }
        }
    }

    /// Dispatch + MemoryLogEngine append cost. This is what an in-app log
    /// inspector pays per call.
    func testHotPathWithMemoryEngine() {
        EngineRegistry.shared.removeAllEngines()
        let memory = MemoryLogEngine(capacity: 50_000)
        SwiftMoLogger.addEngine(memory)
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                SwiftMoLogger.info("with-memory-\(index)")
            }
        }
    }

    /// Verify that level-based filtering short-circuits before any work
    /// happens. Should be ~2× faster than the full hot path.
    func testFilteredByLevelShortCircuit() {
        EngineRegistry.shared.removeAllEngines()
        SwiftMoLogger.addEngine(MemoryLogEngine(capacity: 1_000))
        SwiftMoLogger.minimumLevel = .error
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                SwiftMoLogger.info("filtered-\(index)")
            }
        }
        SwiftMoLogger.minimumLevel = .info
    }

    /// Highly-contended dispatch across many threads. Validates the lock
    /// strategy isn't the bottleneck.
    func testConcurrentDispatchThroughput() {
        EngineRegistry.shared.removeAllEngines()
        let memory = MemoryLogEngine(capacity: 100_000)
        SwiftMoLogger.addEngine(memory)
        let queues = 8
        let perQueue = 2_000

        measure(metrics: [XCTClockMetric()]) {
            let group = DispatchGroup()
            for queueIndex in 0..<queues {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    for entryIndex in 0..<perQueue {
                        SwiftMoLogger.info("q\(queueIndex)-\(entryIndex)")
                    }
                    group.leave()
                }
            }
            group.wait()
        }
    }
}
