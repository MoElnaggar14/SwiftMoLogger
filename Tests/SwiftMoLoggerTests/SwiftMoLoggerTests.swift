import XCTest
@testable import SwiftMoLogger

final class SwiftMoLoggerTests: XCTestCase {
    func testBasicLogging() {
        // Test that basic logging methods don't crash
        SwiftMoLogger.info(message: "Test info message")
        SwiftMoLogger.warn(message: "Test warning message")
        SwiftMoLogger.error(message: "Test error message")
    }
    func testTaggedLogging() {
        // Test that tagged logging methods work
        SwiftMoLogger.info(message: "Test network message", tag: LogTag.Network.api)
        SwiftMoLogger.warn(message: "Test UI message", tag: LogTag.UserInterface.layout)
        SwiftMoLogger.error(message: "Test database message", tag: LogTag.Data.database)
    }
    func testCrashLogging() {
        // Test crash-specific logging
        SwiftMoLogger.crash(message: "Test crash message")
    }
    func testDebugLogging() {
        // Test debug logging (should only work in DEBUG builds)
        SwiftMoLogger.debug(message: "Test debug message")
    }
    func testLogTagNamespaces() {
        // Test that namespace access works
        let networkTag = LogTag.Network.api
        let uiTag = LogTag.UserInterface.navigation
        let dataTag = LogTag.Data.cache
        let securityTag = LogTag.Security.authentication
        XCTAssertEqual(networkTag.rawValue, "[API]")
        XCTAssertEqual(uiTag.rawValue, "[Navigation]")
        XCTAssertEqual(dataTag.rawValue, "[Cache]")
        XCTAssertEqual(securityTag.rawValue, "[Authentication]")
    }
    func testStringTagging() {
        let message = "Test message"
        let taggedMessage = message.tagWith(LogTag.Network.api)
        XCTAssertTrue(taggedMessage.contains("[API]"))
        XCTAssertTrue(taggedMessage.contains("Test message"))
    }
    func testLogTaggedProtocol() {
        struct TestService: LogTagged {
            var logTag: LogTag { LogTag.Network.api }
        }

        let service = TestService()
        // Test that protocol methods don't crash
        service.logInfo("Test info")
        service.logWarn("Test warning")
        service.logError("Test error")
        service.logDebug("Test debug")
    }
    func testMetricKitCrashReporter() {
        let crashReporter = MetricKitCrashReporter()
        // Test that crash reporter can be created and methods called without crashing
        crashReporter.startMonitoring()
        crashReporter.stopMonitoring()
    }
}
