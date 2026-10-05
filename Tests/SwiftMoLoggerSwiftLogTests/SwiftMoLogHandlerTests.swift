import Logging
import SwiftMoLogger
import SwiftMoLoggerSwiftLog
import SwiftMoLoggerTesting
import XCTest

final class SwiftMoLogHandlerTests: XCTestCase {
    private var recorder: RecordingLogEngine!
    private var moLogger: MoLogger!

    override func setUp() {
        super.setUp()
        // An isolated registry: no global state, so this suite can run in parallel.
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        recorder = RecordingLogEngine()
        registry.addEngine(recorder)
        moLogger = MoLogger(registry: registry)
    }

    private func makeLogger(level: Logger.Level = .trace, label: String = "com.example.sync") -> Logger {
        var logger = Logger(label: label) { [moLogger] label in
            SwiftMoLogHandler(label: label, logger: moLogger!)
        }
        logger.logLevel = level
        return logger
    }

    func testForwardsMessageLevelAndLabelTag() throws {
        makeLogger().warning("Retrying")

        let entry = try XCTUnwrap(recorder.recorded().last)
        XCTAssertEqual(entry.message, "Retrying")
        XCTAssertEqual(entry.level, .warning)
        XCTAssertEqual(entry.tag?.domain, "swiftlog.com.example.sync")
        XCTAssertEqual(entry.source.file, #fileID)
    }

    func testRespectsSwiftLogLevel() {
        let logger = makeLogger(level: .error)
        logger.info("dropped")
        logger.error("kept")

        XCTAssertEqual(recorder.recorded().map(\.message), ["kept"])
    }

    func testMergesMetadataWithCallSiteWinning() throws {
        var logger = makeLogger()
        logger[metadataKey: "request_id"] = "abc"
        logger[metadataKey: "attempt"] = "1"

        logger.info("Fetching", metadata: ["attempt": "2", "tags": ["a", "b"], "nested": ["k": "v"]])

        let metadata = try XCTUnwrap(recorder.recorded().last?.metadata)
        XCTAssertEqual(metadata["request_id"], .string("abc"))
        XCTAssertEqual(metadata["attempt"], .string("2"))
        XCTAssertEqual(metadata["tags"], .array([.string("a"), .string("b")]))
        XCTAssertEqual(metadata["nested"], .dictionary(["k": .string("v")]))
        XCTAssertNotNil(metadata["logger.source"])
    }

    func testMetadataProviderContributes() throws {
        let provider = Logger.MetadataProvider { ["trace_id": "t-1"] }
        let logger = Logger(label: "provider") { [moLogger] label in
            SwiftMoLogHandler(label: label, logger: moLogger!, logLevel: .trace, metadataProvider: provider)
        }

        logger.info("hello")

        XCTAssertEqual(recorder.recorded().last?.metadata["trace_id"], .string("t-1"))
    }

    func testLevelMappingCoversEveryLevel() {
        let mapped = Logger.Level.allCases.map(LogLevel.init(swiftLog:))
        XCTAssertEqual(mapped, [.trace, .debug, .info, .notice, .warning, .error, .critical])
    }
}
