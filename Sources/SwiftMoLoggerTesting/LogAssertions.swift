import Foundation
import XCTest
import SwiftMoLogger

/// XCTest assertions for log expectations.
///
/// ```swift
/// final class CheckoutTests: XCTestCase {
///     var logs: RecordingLogEngine!
///     override func setUp() { (log, logs) = MoLogger.recording() }
///
///     func testCheckoutFailureIsLogged() {
///         service.purchase(invalid: true)
///         XCTAssertLogged(.error, contains: "declined", in: logs)
///     }
/// }
/// ```
public func XCTAssertLogged(
    _ level: LogLevel,
    contains substring: String? = nil,
    tag: LogTag? = nil,
    in recorder: RecordingLogEngine,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if !recorder.contains(level, containing: substring, tag: tag) {
        let levelDescription = level.description
        let summary = "Expected log at level \(levelDescription)" +
            (substring.map { " containing \"\($0)\"" } ?? "") +
            (tag.map { " with tag \($0.rawValue)" } ?? "")
        XCTFail("\(summary) — none found. Recorded: \(recorder.recorded().map(\.message))", file: file, line: line)
    }
}

public func XCTAssertNotLogged(
    _ level: LogLevel,
    contains substring: String? = nil,
    in recorder: RecordingLogEngine,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let matches = recorder.entries(level, containing: substring)
    if !matches.isEmpty {
        XCTFail("Expected no log at \(level.description); found: \(matches.map(\.message))", file: file, line: line)
    }
}

public func XCTAssertLogCount(
    _ expected: Int,
    atLevel level: LogLevel? = nil,
    in recorder: RecordingLogEngine,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertEqual(recorder.count(level), expected, file: file, line: line)
}
