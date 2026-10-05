import XCTest
@testable import SwiftMoLogger
import SwiftMoLoggerTesting

/// Regression tests for the 3.1 correctness fixes.
final class CorrectnessTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SwiftMoLogger.reset()
        SwiftMoLogger.minimumLevel = .trace
    }

    // MARK: - Engine identity

    func testTwoMemoryEnginesCoexist() {
        let first = MemoryLogEngine()
        let second = MemoryLogEngine()
        SwiftMoLogger.addEngine(first)
        SwiftMoLogger.addEngine(second)

        SwiftMoLogger.info("hello")

        XCTAssertEqual(SwiftMoLogger.engineCount, 3)
        XCTAssertEqual(first.snapshot().count, 1)
        XCTAssertEqual(second.snapshot().count, 1)
    }

    func testExplicitMemoryEngineIdStillDeduplicates() {
        SwiftMoLogger.addEngine(MemoryLogEngine(id: "mine"))
        SwiftMoLogger.addEngine(MemoryLogEngine(id: "mine"))
        XCTAssertEqual(SwiftMoLogger.engineCount, 2)
    }

    func testDefaultSystemLoggerIsProtectedByIdentityNotPosition() {
        let registry = EngineRegistry()
        let memory = MemoryLogEngine()
        registry.removeAllEngines()
        registry.addEngine(memory)

        // Index 0 is now a user engine and must be removable.
        registry.removeEngine(at: 0)
        XCTAssertEqual(registry.engineCount, 0)

        let fresh = EngineRegistry()
        let systemID = fresh.allEngines()[0].engineID
        XCTAssertFalse(fresh.removeEngine(id: systemID))
        fresh.removeEngine(at: 0)
        XCTAssertEqual(fresh.engineCount, 1)
    }

    func testReplaceEngineKeepsPositionAndCount() {
        let registry = EngineRegistry()
        let memory = MemoryLogEngine()
        registry.addEngine(memory)

        let replaced = registry.replaceEngine(id: memory.engineID) { RedactingLogEngine(wrapping: $0) }

        XCTAssertTrue(replaced)
        XCTAssertEqual(registry.engineCount, 2)
        XCTAssertTrue(registry.allEngines()[1] is RedactingLogEngine)
    }

    func testEnableRedactionIsIdempotentAndKeepsOtherEngines() {
        let memory = MemoryLogEngine()
        SwiftMoLogger.addEngine(memory)

        SwiftMoLogger.enableRedaction(at: 1)
        SwiftMoLogger.enableRedaction(at: 1)
        SwiftMoLogger.info("mail admin@corp.com")

        XCTAssertEqual(SwiftMoLogger.engineCount, 2)
        XCTAssertFalse(memory.snapshot().last?.message.contains("admin@corp.com") ?? true)
    }

    // MARK: - Source location

    func testLevelHelpersForwardColumn() {
        let recorder = SwiftMoLogger.installRecorder()
        SwiftMoLogger.warn("x", column: 42)
        XCTAssertEqual(recorder.recorded().last?.source.column, 42)
    }

    func testSignpostAttributesTheCaller() {
        let recorder = SwiftMoLogger.installRecorder()
        LogSignpost.measure("work") { _ = 1 + 1 }
        XCTAssertEqual(recorder.recorded().last?.source.file, #fileID)
    }

    func testIntervalEndsOnce() {
        let recorder = SwiftMoLogger.installRecorder()
        let interval = LogSignpost.Interval(name: "span")
        interval.end()
        interval.end()
        XCTAssertEqual(recorder.recorded().count, 1)
    }

    // MARK: - Coding

    func testLogTagRoundTripKeepsDomain() throws {
        let data = try JSONEncoder().encode(LogTag.api)
        let decoded = try JSONDecoder().decode(LogTag.self, from: data)
        XCTAssertEqual(decoded.domain, "network.api")
        XCTAssertEqual(decoded, LogTag.api)
    }

    func testLogTagDecodesLegacyBareString() throws {
        let decoded = try JSONDecoder().decode(LogTag.self, from: Data(#""[API]""#.utf8))
        XCTAssertEqual(decoded.rawValue, "[API]")
    }

    func testDatesKeepMilliseconds() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.123)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds

        let decoded = try decoder.decode([Date].self, from: encoder.encode([date]))

        XCTAssertEqual(decoded[0].timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDecoderAcceptsWholeSeconds() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        let decoded = try decoder.decode([Date].self, from: Data(#"["2023-11-14T22:13:20Z"]"#.utf8))
        XCTAssertEqual(decoded[0].timeIntervalSince1970, 1_700_000_000, accuracy: 0.001)
    }

    // MARK: - FileLogEngine

    func testFileEngineWithoutRotatedFiles() throws {
        let url = temporaryURL("no-rotation.log")
        let engine = try FileLogEngine(fileURL: url, maxFileSizeBytes: 200, maxRotatedFiles: 0, minimumLevel: .trace)

        for index in 0..<20 { engine.log(LogEntry(level: .info, message: "line \(index)")) }
        engine.flush()

        XCTAssertEqual(engine.allLogFileURLs(), [url])
    }

    func testFileEngineKeepsWritingAfterRotation() throws {
        let url = temporaryURL("rotating.log")
        let engine = try FileLogEngine(fileURL: url, maxFileSizeBytes: 300, maxRotatedFiles: 2, minimumLevel: .trace)

        for index in 0..<50 { engine.log(LogEntry(level: .info, message: "line \(index)")) }
        engine.flush()

        let files = engine.allLogFileURLs()
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        XCTAssertTrue(contents.contains("line 49"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertLessThanOrEqual(files.count, 3)
    }

    func testFileEnginesInDifferentDirectoriesHaveDifferentIDs() throws {
        let first = try FileLogEngine(fileURL: temporaryURL("a/app.log"))
        let second = try FileLogEngine(fileURL: temporaryURL("b/app.log"))
        XCTAssertNotEqual(first.engineID, second.engineID)
    }

    // MARK: - FlightRecorder

    func testFlightRecorderCanRestartAndStopCleanly() {
        let url = temporaryURL("flight-restart.json")
        let recorder = FlightRecorder(fileURL: url, flushInterval: 60)

        recorder.start()
        recorder.stop()
        recorder.start()
        recorder.stop()

        XCTAssertFalse(UserDefaults.standard.bool(forKey: FlightRecorder.aliveKey(for: url)))
        XCTAssertNil(recorder.crashedSession)
    }

    func testFlightRecorderReportsPreviousCrashAfterStart() {
        let url = temporaryURL("flight-crash.json")
        let crashed = FlightRecorder(fileURL: url, flushInterval: 60)
        crashed.start()
        SwiftMoLogger.error("about to crash")
        crashed.flush()
        // No stop(): simulates the process dying.

        let next = FlightRecorder(fileURL: url, flushInterval: 60)
        next.start()

        XCTAssertEqual(next.crashedSession?.entries.last?.message, "about to crash")
        next.stop()
        crashed.stop()
    }

    func testFlightRecorderOnlyRewritesWhenSomethingChanged() {
        let url = temporaryURL("flight-idle.json")
        let recorder = FlightRecorder(fileURL: url, flushInterval: 60)
        recorder.start()
        defer { recorder.stop() }

        SwiftMoLogger.error("first")
        XCTAssertTrue(recorder.flushIfChanged())
        XCTAssertFalse(recorder.flushIfChanged(), "an unchanged snapshot was rewritten")

        SwiftMoLogger.error("second")
        XCTAssertTrue(recorder.flushIfChanged())
    }

    func testTwoEnginesOnOneFileKeepEveryLineIntact() throws {
        let url = temporaryURL("shared.log")
        let first = try FileLogEngine(fileURL: url, maxFileSizeBytes: 1_000_000, minimumLevel: .trace)
        let second = try FileLogEngine(fileURL: url, maxFileSizeBytes: 1_000_000, minimumLevel: .trace)

        for index in 0..<50 {
            (index.isMultiple(of: 2) ? first : second).log(LogEntry(level: .info, message: "line-\(index)"))
        }
        first.flush()
        second.flush()

        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 50)
        for line in lines {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
    }

    // MARK: - Error grouping

    func testErrorGroupingIsBounded() {
        let grouping = ErrorGroupingEngine(wrapping: MemoryLogEngine(), maxGroups: 10)
        // Distinct shapes the normaliser can't collapse (no digits, hex or quotes).
        for index in 0..<100 {
            grouping.log(LogEntry(level: .error, message: "failure in m" + String(repeating: "q", count: index)))
        }
        XCTAssertLessThanOrEqual(grouping.snapshot().count, 10)
    }

    // MARK: - Helpers

    private func temporaryURL(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftMoLoggerTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(name)
    }
}
