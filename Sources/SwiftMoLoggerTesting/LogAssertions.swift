import Foundation
import XCTest
import SwiftMoLogger

/// XCTest assertions for log expectations.
///
/// ```swift
/// final class CheckoutTests: XCTestCase {
///     var logs: RecordingLogEngine!
///     override func setUp() { logs = SwiftMoLogger.installRecorder() }
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
    file: StaticString = #file,
    line: UInt = #line
) {
    let matches = recorder.recorded().filter { entry in
        guard entry.level == level else { return false }
        if let substring = substring, !entry.message.contains(substring) { return false }
        if let tag = tag, entry.tag?.domain != tag.domain { return false }
        return true
    }
    if matches.isEmpty {
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
    file: StaticString = #file,
    line: UInt = #line
) {
    let matches = recorder.recorded().filter { entry in
        guard entry.level == level else { return false }
        if let substring = substring, !entry.message.contains(substring) { return false }
        return true
    }
    if !matches.isEmpty {
        XCTFail("Expected no log at \(level.description); found: \(matches.map(\.message))", file: file, line: line)
    }
}

public func XCTAssertLogCount(
    _ expected: Int,
    atLevel level: LogLevel? = nil,
    in recorder: RecordingLogEngine,
    file: StaticString = #file,
    line: UInt = #line
) {
    let count: Int
    if let level = level {
        count = recorder.recorded().filter { $0.level == level }.count
    } else {
        count = recorder.recorded().count
    }
    XCTAssertEqual(count, expected, file: file, line: line)
}
