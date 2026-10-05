import XCTest
@testable import SwiftMoLogger

/// Performance baselines. Numbers documented in `PERFORMANCE.md` are
/// regenerated from these tests; treat regressions in CI as a hard failure
/// once the baseline is checked in via XCTest performance metrics.
final class PerformanceBenchmarks: LoggingTestCase {

    override func setUp() {
        super.setUp()
        registry.removeEngine(at: 0)
        registry.minimumLevel = .info
    }

    /// Lower bound: pure dispatch cost with no engines attached.
    func testHotPathWithNoEngines() {
        registry.removeAllEngines()
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                log.info("hot-path-\(index)")
            }
        }
    }

    /// Dispatch + MemoryLogEngine append cost. This is what an in-app log
    /// inspector pays per call.
    func testHotPathWithMemoryEngine() {
        registry.removeAllEngines()
        let memory = MemoryLogEngine(capacity: 50_000)
        registry.addEngine(memory)
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                log.info("with-memory-\(index)")
            }
        }
    }

    /// Verify that level-based filtering short-circuits before any work
    /// happens. Should be ~2× faster than the full hot path.
    func testFilteredByLevelShortCircuit() {
        registry.removeAllEngines()
        registry.addEngine(MemoryLogEngine(capacity: 1_000))
        registry.minimumLevel = .error
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                log.info("filtered-\(index)")
            }
        }
        registry.minimumLevel = .info
    }

    /// Highly-contended dispatch across many threads. Validates the lock
    /// strategy isn't the bottleneck.
    func testConcurrentDispatchThroughput() {
        registry.removeAllEngines()
        let memory = MemoryLogEngine(capacity: 100_000)
        registry.addEngine(memory)
        let queues = 8
        let perQueue = 2_000
        let log = self.log

        measure(metrics: [XCTClockMetric()]) {
            let group = DispatchGroup()
            for queueIndex in 0..<queues {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    for entryIndex in 0..<perQueue {
                        log.info("q\(queueIndex)-\(entryIndex)")
                    }
                    group.leave()
                }
            }
            group.wait()
        }
    }
}
