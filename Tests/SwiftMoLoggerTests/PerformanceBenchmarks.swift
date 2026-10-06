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

    /// Filtering with per-tag overrides in place: a short scan of the override
    /// keys, still before the message is built. Should stay close to
    /// `testFilteredByLevelShortCircuit`.
    func testFilteredWithLevelOverrides() {
        registry.removeAllEngines()
        registry.addEngine(MemoryLogEngine(capacity: 1_000))
        registry.minimumLevel = .error
        registry.levelOverrides = ["data.database": .trace, "network": .warning, "thirdparty": .fault]
        let tagged = log.with(tag: .UI.navigation)
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                tagged.info("filtered-\(index)")
            }
        }
        registry.levelOverrides = LevelOverrides()
        registry.minimumLevel = .info
    }

    /// A `LogMessage` with a private value: the second rendering plus the
    /// `revealsPrivateValues` read. Compare with `testHotPathWithMemoryEngine`.
    func testHotPathWithPrivateValue() {
        registry.removeAllEngines()
        registry.addEngine(MemoryLogEngine(capacity: 50_000))
        let email = "mo@example.com"
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                log.info("private-\(index) \(email, privacy: .private)")
            }
        }
    }

    /// A filtered `LogMessage` call: same short-circuit as the `String` overload,
    /// the interpolation never runs.
    func testFilteredPrivateValue() {
        registry.removeAllEngines()
        registry.addEngine(MemoryLogEngine(capacity: 1_000))
        registry.minimumLevel = .error
        let email = "mo@example.com"
        measure(metrics: [XCTClockMetric()]) {
            for index in 0..<10_000 {
                log.info("filtered-\(index) \(email, privacy: .private)")
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
