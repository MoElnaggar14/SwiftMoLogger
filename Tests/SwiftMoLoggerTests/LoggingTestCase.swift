import XCTest
import SwiftMoLogger
import SwiftMoLoggerTesting

/// Gives every test its own ``LogEnvironment``: no global state, so suites
/// are independent and can run in parallel.
class LoggingTestCase: XCTestCase {
    private(set) var environment: LogEnvironment!
    var registry: EngineRegistry { environment.registry }
    var log: MoLogger { environment.logger }

    override func setUp() {
        super.setUp()
        environment = LogEnvironment()
    }

    override func tearDown() {
        environment = nil
        super.tearDown()
    }

    /// Replaces every engine in this test's registry with a recorder.
    func installRecorder() -> RecordingLogEngine {
        let recorder = RecordingLogEngine()
        registry.removeAllEngines()
        registry.addEngine(recorder)
        return recorder
    }
}
