import XCTest
import SwiftMoLogger
import SwiftMoLoggerTesting

/// `MoLogger` tests use their own registry, so they never touch global state.
final class MoLoggerTests: XCTestCase {
    private func makeLogger() -> (MoLogger, RecordingLogEngine, EngineRegistry) {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        let recorder = RecordingLogEngine()
        registry.addEngine(recorder)
        return (MoLogger(registry: registry), recorder, registry)
    }

    func testLogsToItsOwnRegistryOnly() {
        let (logger, recorder, _) = makeLogger()
        let global = SwiftMoLogger.installRecorder()
        defer { SwiftMoLogger.reset() }

        logger.info("isolated")

        XCTAssertEqual(recorder.recorded().map(\.message), ["isolated"])
        XCTAssertFalse(global.recorded().contains { $0.message == "isolated" })
    }

    func testChildLoggerAppliesTagAndMergesMetadata() throws {
        let (base, recorder, _) = makeLogger()
        let child = base
            .with(tag: .api)
            .with(metadata: ["component": "checkout", "region": "eu"])

        child.warning("slow", metadata: ["region": "us"])

        let entry = try XCTUnwrap(recorder.recorded().last)
        XCTAssertEqual(entry.tag, .api)
        XCTAssertEqual(entry.metadata["component"], .string("checkout"))
        XCTAssertEqual(entry.metadata["region"], .string("us"))
        XCTAssertEqual(entry.level, .warning)
    }

    func testExplicitTagOverridesDefault() {
        let (base, recorder, _) = makeLogger()
        base.with(tag: .api).info("x", tag: .database)
        XCTAssertEqual(recorder.recorded().last?.tag, .database)
    }

    func testRegistryMinimumLevelSkipsMessageEvaluation() {
        let (logger, recorder, registry) = makeLogger()
        registry.minimumLevel = .error
        var evaluated = false

        logger.info({ evaluated = true; return "expensive" }())

        XCTAssertFalse(evaluated)
        XCTAssertTrue(recorder.recorded().isEmpty)
    }

    func testErrorOverloadAddsErrorMetadata() throws {
        struct Boom: Error {}
        let (logger, recorder, _) = makeLogger()

        logger.error(Boom())

        let entry = try XCTUnwrap(recorder.recorded().last)
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.metadata["error_type"], .string("Boom"))
    }

    func testStaticFacadeStillUsesSharedRegistry() {
        let recorder = SwiftMoLogger.installRecorder()
        defer { SwiftMoLogger.reset() }

        SwiftMoLogger.info("through facade", column: 9)

        XCTAssertEqual(recorder.recorded().last?.message, "through facade")
        XCTAssertEqual(recorder.recorded().last?.source.column, 9)
    }
}
