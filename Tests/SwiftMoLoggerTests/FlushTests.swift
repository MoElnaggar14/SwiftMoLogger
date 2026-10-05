import Foundation
import SwiftMoLogger
import Testing

/// Counts flushes; logs nothing.
private final class FlushCountingEngine: LogEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var flushCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func log(_ entry: LogEntry) {}

    func flush() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

/// An engine written before 4.0 added `flush()`: it must still compile and be flushable.
private final class LegacyEngine: LogEngine, @unchecked Sendable {
    func log(_ entry: LogEntry) {}
}

@Suite("Flushing engines")
struct FlushTests {
    @Test func registryFlushReachesEveryEngineThroughDecorators() {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        let direct = FlushCountingEngine()
        let decorated = FlushCountingEngine()
        registry.addEngine(direct)
        registry.addEngine(LegacyEngine())
        registry.addEngine(
            RateLimitingLogEngine(
                wrapping: ErrorGroupingEngine(
                    wrapping: SamplingLogEngine(
                        wrapping: RedactingLogEngine(wrapping: decorated),
                        strategy: .uniform(rate: 1)
                    )
                ),
                permitsPerSecond: 10
            )
        )

        registry.flush()

        #expect(direct.flushCount == 1)
        #expect(decorated.flushCount == 1)
    }

    @Test func flushWritesFileEntriesToDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flush-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: url) }
        let logging = LogEnvironment(registry: EngineRegistry(installDefaultSystemLogger: false))
        logging.registry.addEngine(try FileLogEngine(fileURL: url))

        logging.logger.info("written before backgrounding")
        logging.registry.flush()

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("written before backgrounding"))
    }
}
