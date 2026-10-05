import XCTest
@testable import SwiftMoLogger

final class TraceContextTests: LoggingTestCase {

    func testGenerateProducesValidTraceparent() {
        let context = TraceContext.generate()
        XCTAssertEqual(context.traceID.count, 32)
        XCTAssertEqual(context.spanID.count, 16)
        let parts = context.traceparent.split(separator: "-")
        XCTAssertEqual(parts.count, 4)
        XCTAssertEqual(parts[0], "00")
    }

    func testRoundTripParse() {
        let original = TraceContext.generate(sampled: true)
        let parsed = TraceContext.parse(traceparent: original.traceparent)
        XCTAssertEqual(parsed?.traceID, original.traceID)
        XCTAssertEqual(parsed?.spanID, original.spanID)
        XCTAssertEqual(parsed?.sampled, true)
    }

    func testParseRejectsMalformed() {
        XCTAssertNil(TraceContext.parse(traceparent: "garbage"))
        XCTAssertNil(TraceContext.parse(traceparent: "00-tooshort-tooshort-00"))
    }

    func testInvalidIDsAreRejectedInsteadOfCrashing() {
        let span = "00f067aa0ba902b7"
        let trace = "4bf92f3577b34da6a3ce929d0e0e4736"
        XCTAssertNotNil(TraceContext(traceID: trace, spanID: span))
        XCTAssertNil(TraceContext(traceID: "short", spanID: span))
        XCTAssertNil(TraceContext(traceID: String(repeating: "z", count: 32), spanID: span), "not hex")
        XCTAssertNil(TraceContext(traceID: String(repeating: "0", count: 32), spanID: span), "all zeros")
        XCTAssertNil(TraceContext.parse(traceparent: "00-\(trace)-0000000000000000-01"))
        XCTAssertEqual(TraceContext(traceID: trace.uppercased(), spanID: span)?.traceID, trace)
    }

    func testDuplicateMetadataKeysKeepTheLastValue() {
        let metadata: LogMetadata = ["key": "first", "key": "second"]
        XCTAssertEqual(metadata["key"], .string("second"))
    }

    func testChildSpanKeepsTraceID() {
        let parent = TraceContext.generate()
        let child = parent.childSpan()
        XCTAssertEqual(child.traceID, parent.traceID)
        XCTAssertNotEqual(child.spanID, parent.spanID)
    }

    func testWithTraceStampsLogEntries() {
        let memory = MemoryLogEngine()
        registry.addEngine(memory)
        let context = TraceContext.generate()

        context.run {
            log.info("in trace")
        }
        log.info("outside trace")

        let entries = memory.snapshot()
        let inside = entries.first { $0.message == "in trace" }
        let outside = entries.first { $0.message == "outside trace" }
        XCTAssertEqual(inside?.metadata["trace.id"], .string(context.traceID))
        XCTAssertNil(outside?.metadata["trace.id"])
    }
}

final class ErrorGroupingEngineTests: LoggingTestCase {

    func testIdenticalShapeCollapses() {
        let memory = MemoryLogEngine()
        let grouper = ErrorGroupingEngine(wrapping: memory, emitThreshold: 1)
        for index in 0..<5 {
            grouper.log(LogEntry(level: .error, message: "User \(index) timed out", tag: .api))
        }
        XCTAssertEqual(memory.snapshot().count, 1, "Only first occurrence forwarded")
        let groups = grouper.snapshot()
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.count, 5)
    }

    func testDifferentShapesProduceSeparateGroups() {
        let memory = MemoryLogEngine()
        let grouper = ErrorGroupingEngine(wrapping: memory)
        grouper.log(LogEntry(level: .error, message: "DB connection refused", tag: .database))
        grouper.log(LogEntry(level: .error, message: "Payment declined", tag: .api))
        XCTAssertEqual(grouper.snapshot().count, 2)
    }

    func testLowerSeveritiesPassThroughUnchanged() {
        let memory = MemoryLogEngine()
        let grouper = ErrorGroupingEngine(wrapping: memory, fingerprintMinLevel: .error)
        for _ in 0..<5 {
            grouper.log(LogEntry(level: .info, message: "noise"))
        }
        XCTAssertEqual(memory.snapshot().count, 5)
    }

    func testNormaliseStripsUUIDsAndNumbers() {
        let raw = "Order 4521-AB failed for user 11111111-2222-3333-4444-555555555555 after 320ms"
        let normalised = ErrorGroupingEngine.normalise(raw)
        XCTAssertFalse(normalised.contains("4521"))
        XCTAssertFalse(normalised.contains("320"))
        XCTAssertTrue(normalised.contains("<uuid>"))
        XCTAssertTrue(normalised.contains("#"))
    }
}

final class FlightRecorderTests: LoggingTestCase {

    override func setUp() {
        super.setUp()
        // Reset the global registry so other suites' leftover engines or
        // raised `minimumLevel` don't suppress the entries this recorder
        // is supposed to capture.
        registry.minimumLevel = .trace
    }

    func testFlushWritesJSONFile() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fr-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let recorder = FlightRecorder(environment: environment, fileURL: tmpURL, window: 60, flushInterval: 60)
        recorder.start()
        log.info("flight test")
        recorder.flush()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpURL.path))
        let data = try Data(contentsOf: tmpURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        let session = try? decoder.decode(FlightRecorder.Session.self, from: data)
        XCTAssertNotNil(session)
        XCTAssertTrue(session?.entries.contains { $0.message == "flight test" } ?? false)
        recorder.stop()
    }

    func testCleanStopRemovesArtifact() {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fr-stop-\(UUID().uuidString).json")
        let recorder = FlightRecorder(environment: environment, fileURL: tmpURL, window: 60, flushInterval: 60)
        recorder.start()
        log.info("will be wiped")
        recorder.flush()
        recorder.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpURL.path))
    }
}
