import XCTest
@testable import SwiftMoLogger
import SwiftMoLoggerTesting

/// Regression tests for the 3.1 correctness fixes.
final class CorrectnessTests: LoggingTestCase {
    override func setUp() {
        super.setUp()
        registry.minimumLevel = .trace
    }

    // MARK: - Engine identity

    func testTwoMemoryEnginesCoexist() {
        let first = MemoryLogEngine()
        let second = MemoryLogEngine()
        registry.addEngine(first)
        registry.addEngine(second)

        log.info("hello")

        // System logger + stream + both memory engines.
        XCTAssertEqual(registry.engineCount, 4)
        XCTAssertEqual(first.snapshot().count, 1)
        XCTAssertEqual(second.snapshot().count, 1)
    }

    func testExplicitMemoryEngineIdStillDeduplicates() {
        registry.addEngine(MemoryLogEngine(id: "mine"))
        registry.addEngine(MemoryLogEngine(id: "mine"))
        XCTAssertEqual(registry.engineCount, 3)
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
        registry.addEngine(memory)

        let index = registry.allEngines().firstIndex { $0 === memory }!
        registry.enableRedaction(at: index)
        registry.enableRedaction(at: index)
        log.info("mail admin@corp.com")

        XCTAssertEqual(registry.engineCount, 3)
        XCTAssertFalse(memory.snapshot().last?.message.contains("admin@corp.com") ?? true)
    }

    // MARK: - Source location

    func testLevelHelpersForwardColumn() {
        let recorder = installRecorder()
        log.warning("x", column: 42)
        XCTAssertEqual(recorder.recorded().last?.source.column, 42)
    }

    func testSignpostAttributesTheCaller() {
        let recorder = installRecorder()
        environment.signposter.measure("work") { _ = 1 + 1 }
        XCTAssertEqual(recorder.recorded().last?.source.file, #fileID)
    }

    func testIntervalEndsOnce() {
        let recorder = installRecorder()
        let interval = environment.signposter.makeInterval("span")
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
        let defaults = isolatedDefaults()
        let recorder = FlightRecorder(environment: environment, fileURL: url, flushInterval: 60, defaults: defaults)

        recorder.start()
        recorder.stop()
        recorder.start()
        recorder.stop()

        XCTAssertFalse(defaults.bool(forKey: "SwiftMoLogger.FlightRecorder.alive"))
        XCTAssertNil(recorder.crashedSession)
    }

    func testFlightRecorderReportsPreviousCrashAfterStart() {
        let url = temporaryURL("flight-crash.json")
        let defaults = isolatedDefaults()
        let crashed = FlightRecorder(environment: environment, fileURL: url, flushInterval: 60, defaults: defaults)
        crashed.start()
        log.error("about to crash")
        crashed.flush()
        // No stop(): simulates the process dying.

        let next = FlightRecorder(environment: environment, fileURL: url, flushInterval: 60, defaults: defaults)
        next.start()

        XCTAssertEqual(next.crashedSession?.entries.last?.message, "about to crash")
        next.stop()
        crashed.stop()
    }

    func testFlightRecorderCanRedactBeforePersisting() throws {
        let url = temporaryURL("flight-redacted.json")
        let recorder = FlightRecorder(
            environment: environment,
            fileURL: url,
            flushInterval: 60,
            defaults: isolatedDefaults(),
            redactor: Redactor()
        )
        recorder.start()
        log.info("contact admin@corp.com")
        recorder.flush()

        let persisted = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(persisted.contains("admin@corp.com"))
        recorder.stop()
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

    private func isolatedDefaults() -> UserDefaults {
        let suite = "SwiftMoLoggerTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    private func temporaryURL(_ name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftMoLoggerTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent(name)
    }
}
