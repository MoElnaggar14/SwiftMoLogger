import XCTest
@testable import SwiftMoLogger

final class SwiftMoLoggerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Reset to clean state
        SwiftMoLogger.reset()
    }

    func testBasicLogging() {
        // Test that basic logging methods don't crash
        SwiftMoLogger.info("Test info message")
        SwiftMoLogger.warn("Test warning message")
        SwiftMoLogger.error("Test error message")
    }

    func testTaggedLogging() {
        // Test that tagged logging methods work
        SwiftMoLogger.info("Test network message", tag: .api)
        SwiftMoLogger.warn("Test UI message", tag: .layout)
        SwiftMoLogger.error("Test database message", tag: .database)
    }

    func testCrashLogging() {
        // Test crash-specific logging
        SwiftMoLogger.crash("Test crash message")
    }

    func testDebugLogging() {
        // Test debug logging (should only work in DEBUG builds)
        SwiftMoLogger.debug("Test debug message")
    }

    func testLogTags() {
        // Test that tags have correct raw values
        XCTAssertEqual(LogTag.api.rawValue, "[API]")
        XCTAssertEqual(LogTag.navigation.rawValue, "[Navigation]")
        XCTAssertEqual(LogTag.cache.rawValue, "[Cache]")
        XCTAssertEqual(LogTag.authentication.rawValue, "[Authentication]")
    }

    func testLogTaggedProtocol() {
        struct TestService: LogTagged {
            var logTag: LogTag { .api }
        }

        let service = TestService()
        service.logInfo("Test info")
        service.logWarn("Test warning")
        service.logError("Test error")
        service.logDebug("Test debug")
    }

    func testEngineManagement() {
        // Test engine registry
        let initialCount = SwiftMoLogger.engineCount
        XCTAssertEqual(initialCount, 1) // SystemLogger

        // Add a test engine
        let testEngine = TestLogEngine()
        SwiftMoLogger.addEngine(testEngine)
        XCTAssertEqual(SwiftMoLogger.engineCount, 2)

        // Remove engine
        SwiftMoLogger.removeEngine(at: 1) // Remove custom engine
        XCTAssertEqual(SwiftMoLogger.engineCount, 1)
    }

    func testCustomEngine() {
        let testEngine = TestLogEngine()
        SwiftMoLogger.addEngine(testEngine)

        SwiftMoLogger.info("Test message")
        SwiftMoLogger.warn("Warning message")
        SwiftMoLogger.error("Error message")

        // Verify messages were captured
        XCTAssertEqual(testEngine.messages.count, 3)
        XCTAssertTrue(testEngine.messages.contains("Test message"))
        XCTAssertTrue(testEngine.messages.contains("Warning message"))
        XCTAssertTrue(testEngine.messages.contains("Error message"))
    }

    func testMetricKitCrashReporter() {
        let crashReporter = MetricKitCrashReporter()
        crashReporter.startMonitoring()
        crashReporter.stopMonitoring()
    }
}

// MARK: - Test Engine

class TestLogEngine: LogEngine {
    private(set) var messages: [String] = []

    func info(message: String) {
        messages.append(message)
    }

    func warn(message: String) {
        messages.append(message)
    }

    func error(message: String) {
        messages.append(message)
    }
}
