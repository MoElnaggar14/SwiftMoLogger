import XCTest
@testable import SwiftMoLogger

final class SwiftMoLoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftMoLogger.reset()
    }

    func testBasicLogging() {
        SwiftMoLogger.info("info")
        SwiftMoLogger.warn("warn")
        SwiftMoLogger.error("error")
    }

    func testTaggedLogging() {
        SwiftMoLogger.info("api call", tag: .api)
        SwiftMoLogger.warn("layout warning", tag: .layout)
        SwiftMoLogger.error("db error", tag: .database)
    }

    func testStructuredLogging() {
        let memory = MemoryLogEngine(capacity: 32)
        SwiftMoLogger.addEngine(memory)

        SwiftMoLogger.error("payment failed", tag: .api, metadata: [
            "order_id": "ord_123",
            "amount": 49.99,
            "retried": true
        ])

        let entries = memory.snapshot()
        guard let last = entries.last else {
            XCTFail("No entry captured")
            return
        }
        XCTAssertEqual(last.level, .error)
        XCTAssertEqual(last.tag?.rawValue, "[API]")
        XCTAssertEqual(last.metadata["order_id"], .string("ord_123"))
        XCTAssertEqual(last.metadata["amount"], .double(49.99))
        XCTAssertEqual(last.metadata["retried"], .bool(true))
    }

    func testErrorOverload() {
        struct BoomError: LocalizedError {
            var errorDescription: String? { "kaboom" }
        }
        let memory = MemoryLogEngine(capacity: 4)
        SwiftMoLogger.addEngine(memory)

        SwiftMoLogger.error(BoomError(), tag: .api)
        let entry = memory.snapshot().last
        XCTAssertEqual(entry?.message, "kaboom")
        XCTAssertEqual(entry?.metadata["error_type"], .string("BoomError"))
    }

    func testGlobalMinimumLevelFilters() {
        let memory = MemoryLogEngine(capacity: 16)
        SwiftMoLogger.addEngine(memory)

        SwiftMoLogger.minimumLevel = .warning
        SwiftMoLogger.info("dropped")
        SwiftMoLogger.warn("kept")
        SwiftMoLogger.error("kept")
        SwiftMoLogger.minimumLevel = .trace

        let messages = memory.snapshot().map(\.message)
        XCTAssertFalse(messages.contains("dropped"))
        XCTAssertTrue(messages.contains("kept"))
    }

    func testLogTagDomains() {
        XCTAssertEqual(LogTag.api.rawValue, "[API]")
        XCTAssertEqual(LogTag.api.domain, "network.api")
        XCTAssertEqual(LogTag.Network.websocket.rawValue, "[WebSocket]")
        XCTAssertEqual(LogTag.custom("Feature").rawValue, "[Feature]")
    }

    func testLogLevelOrdering() {
        XCTAssertLessThan(LogLevel.trace, LogLevel.debug)
        XCTAssertLessThan(LogLevel.debug, LogLevel.info)
        XCTAssertLessThan(LogLevel.warning, LogLevel.error)
        XCTAssertLessThan(LogLevel.error, LogLevel.fault)
    }

    func testLogTaggedProtocol() {
        struct APIService: LogTagged {
            var logTag: LogTag { .api }
        }
        let memory = MemoryLogEngine(capacity: 4)
        SwiftMoLogger.addEngine(memory)
        let service = APIService()
        service.logInfo("hello")
        XCTAssertEqual(memory.snapshot().last?.tag?.rawValue, "[API]")
    }

    func testEngineManagement() {
        XCTAssertEqual(SwiftMoLogger.engineCount, 1)
        let mem = MemoryLogEngine()
        SwiftMoLogger.addEngine(mem)
        XCTAssertEqual(SwiftMoLogger.engineCount, 2)

        // Re-adding by id replaces, not duplicates.
        SwiftMoLogger.addEngine(mem)
        XCTAssertEqual(SwiftMoLogger.engineCount, 2)

        SwiftMoLogger.removeEngine(id: mem.engineID)
        XCTAssertEqual(SwiftMoLogger.engineCount, 1)
    }

    func testRemoveEngineDoesNotRemoveSystemLogger() {
        SwiftMoLogger.removeEngine(at: 0)
        XCTAssertEqual(SwiftMoLogger.engineCount, 1)
    }

    func testAmbientContext() {
        let memory = MemoryLogEngine(capacity: 4)
        SwiftMoLogger.addEngine(memory)

        SwiftMoLogger.withContext(["request_id": "req-42"]) {
            SwiftMoLogger.info("scoped")
        }
        SwiftMoLogger.info("outside")

        let entries = memory.snapshot()
        let scoped = entries.first { $0.message == "scoped" }
        let outside = entries.first { $0.message == "outside" }
        XCTAssertEqual(scoped?.metadata["request_id"], .string("req-42"))
        XCTAssertNil(outside?.metadata["request_id"])
    }

    func testMemoryEngineCircularBuffer() {
        let memory = MemoryLogEngine(capacity: 3)
        SwiftMoLogger.addEngine(memory)
        for index in 0..<10 {
            SwiftMoLogger.info("msg-\(index)")
        }
        let snapshot = memory.snapshot()
        XCTAssertEqual(snapshot.count, 3)
        XCTAssertEqual(snapshot.map(\.message), ["msg-7", "msg-8", "msg-9"])
    }

    func testMemoryEngineCounters() {
        let memory = MemoryLogEngine(capacity: 16)
        SwiftMoLogger.addEngine(memory)
        SwiftMoLogger.info("i")
        SwiftMoLogger.warn("w")
        SwiftMoLogger.warn("w2")
        SwiftMoLogger.error("e")
        let counters = memory.counters()
        XCTAssertEqual(counters.total, 4)
        XCTAssertEqual(counters.warnings, 2)
        XCTAssertEqual(counters.errors, 1)
    }

    func testMemoryEngineFiltering() {
        let memory = MemoryLogEngine(capacity: 16)
        SwiftMoLogger.addEngine(memory)
        SwiftMoLogger.info("net stuff", tag: .network)
        SwiftMoLogger.error("auth boom", tag: .authentication)
        SwiftMoLogger.warn("net warning", tag: .network)

        let onlyNetwork = memory.filtered(domain: "network")
        XCTAssertEqual(onlyNetwork.count, 2)

        let errorsOnly = memory.filtered(minLevel: .error)
        XCTAssertEqual(errorsOnly.count, 1)

        let contains = memory.filtered(contains: "auth")
        XCTAssertEqual(contains.count, 1)
    }

    func testFileEngineWritesJSONLines() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("smologger-\(UUID().uuidString).log")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let engine = try FileLogEngine(fileURL: tmp, maxFileSizeBytes: 10_000)
        SwiftMoLogger.addEngine(engine)
        SwiftMoLogger.info("hello-file", tag: .api, metadata: ["k": "v"])
        engine.flush()

        let raw = try String(contentsOf: tmp)
        XCTAssertTrue(raw.contains("hello-file"))
        XCTAssertTrue(raw.contains("\"level\""))
        XCTAssertTrue(raw.hasSuffix("\n"))
    }

    func testFileEngineRotates() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("smologger-rot-\(UUID().uuidString).log")
        defer {
            try? FileManager.default.removeItem(at: tmp)
            for index in 1...3 {
                let url = tmp.deletingLastPathComponent()
                    .appendingPathComponent("\(tmp.lastPathComponent).\(index)")
                try? FileManager.default.removeItem(at: url)
            }
        }

        let engine = try FileLogEngine(fileURL: tmp, maxFileSizeBytes: 256, maxRotatedFiles: 2)
        SwiftMoLogger.addEngine(engine)
        for index in 0..<50 {
            SwiftMoLogger.info("rotation-test-entry-with-enough-bytes-\(index)")
        }
        engine.flush()

        let urls = engine.allLogFileURLs()
        XCTAssertGreaterThan(urls.count, 1, "Expected rotation to produce multiple files")
    }

    func testConcurrentLoggingDoesNotCrash() {
        let memory = MemoryLogEngine(capacity: 5_000)
        SwiftMoLogger.addEngine(memory)

        let iterations = 200
        let queues = 8
        let expectation = expectation(description: "concurrent")
        expectation.expectedFulfillmentCount = queues

        for queueIndex in 0..<queues {
            DispatchQueue.global(qos: .userInitiated).async {
                for entryIndex in 0..<iterations {
                    SwiftMoLogger.info("q\(queueIndex)-\(entryIndex)")
                }
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 10)

        XCTAssertEqual(memory.counters().total, queues * iterations)
    }

    func testAsyncStreamSubscription() async {
        let stream = SwiftMoLogger.stream(bufferSize: 16)
        let task = Task<[LogEntry], Never> {
            var collected: [LogEntry] = []
            for await entry in stream {
                collected.append(entry)
                if collected.count == 3 { break }
            }
            return collected
        }
        // Give the stream a beat to be wired up.
        try? await Task.sleep(nanoseconds: 50_000_000)
        SwiftMoLogger.info("s1")
        SwiftMoLogger.info("s2")
        SwiftMoLogger.info("s3")

        let collected = await task.value
        XCTAssertEqual(collected.count, 3)
        XCTAssertEqual(collected.map(\.message), ["s1", "s2", "s3"])
    }

    #if canImport(MetricKit) && (os(iOS) || os(macOS))
    func testMetricKitCrashReporterLifecycle() {
        let reporter = MetricKitCrashReporter()
        reporter.startMonitoring()
        reporter.stopMonitoring()
    }
    #endif
}

// Legacy LogEngine adapter used as a smoke-test that the deprecated
// info/warn/error overloads still flow through `log(_:)`.
private final class LegacyAdapter: LogEngine, @unchecked Sendable {
    var captured: [(String, LogLevel)] = []
    func log(_ entry: LogEntry) {
        captured.append((entry.message, entry.level))
    }
}

extension SwiftMoLoggerTests {
    func testLegacyProtocolDefaultsRouteThroughLogEntry() {
        let adapter = LegacyAdapter()
        adapter.info(message: "i")
        adapter.warn(message: "w")
        adapter.error(message: "e")
        XCTAssertEqual(adapter.captured.map(\.0), ["i", "w", "e"])
        XCTAssertEqual(adapter.captured.map(\.1), [.info, .warning, .error])
    }
}
