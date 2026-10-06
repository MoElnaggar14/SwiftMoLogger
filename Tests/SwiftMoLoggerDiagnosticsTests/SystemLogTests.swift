import Foundation
import OSLog
import SwiftMoLogger
@testable import SwiftMoLoggerDiagnostics
import Testing

/// Returns canned entries and records the date it was asked for.
private final class FakeSystemLog: SystemLogSource, @unchecked Sendable {
    // @unchecked Sendable: `requested` is only touched from the test's own task.
    let entries: [SystemLogEntry]
    let error: (any Error)?
    var requested: Date?

    init(_ entries: [SystemLogEntry] = [], error: (any Error)? = nil) {
        self.entries = entries
        self.error = error
    }

    func entries(since date: Date) throws -> [SystemLogEntry] {
        requested = date
        if let error { throw error }
        return entries
    }
}

private struct StoreClosed: LocalizedError {
    var errorDescription: String? { "the store is closed" }
}

@Suite("System log in bug reports")
struct SystemLogTests {
    private func entry(_ message: String, at seconds: TimeInterval = 0, level: LogLevel = .error) -> SystemLogEntry {
        SystemLogEntry(
            date: Date(timeIntervalSince1970: 1_700_000_000 + seconds),
            level: level,
            subsystem: "com.apple.network",
            category: "connection",
            message: message
        )
    }

    private func systemLogFile(_ reporter: BugReporter) throws -> String? {
        let report = try reporter.generate()
        defer { try? FileManager.default.removeItem(at: report.directory) }
        let url = report.directory.appendingPathComponent("system-log.txt")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test func linesShowTimeLevelSourceAndMessage() {
        let text = SystemLogOptions().render([entry("Task failed", at: 0.5)])
        #expect(text == "2023-11-14T22:13:20.500Z ERROR [com.apple.network connection] Task failed")
    }

    @Test func messagesAreRedacted() {
        let text = SystemLogOptions().render([entry("login failed for jane@example.com")])
        #expect(!text.contains("jane@example.com"))
    }

    @Test func newestEntriesAreKeptWithinTheByteLimit() {
        let entries = (0..<10).map { entry("message \($0)", at: Double($0)) }
        let options = SystemLogOptions(maxBytes: 200)
        let lines = options.render(entries).split(separator: "\n").map(String.init)

        #expect(lines.first?.hasPrefix("… ") == true, "a header says older entries were left out")
        #expect(lines.last?.hasSuffix("message 9") == true)
        #expect(!lines.contains { $0.hasSuffix("message 0") })
        let kept = lines.count - 1
        #expect(lines.first == "… \(10 - kept) earlier entries left out to stay under 200 bytes")
    }

    @Test func emptySubsystemAndCategoryStillRender() {
        let bare = SystemLogEntry(
            date: Date(timeIntervalSince1970: 0), level: .info, subsystem: "", category: "", message: "hi"
        )
        #expect(SystemLogOptions().render([bare]).hasSuffix("INFO [] hi"))
    }

    @Test func reportReadsTheConfiguredWindow() throws {
        let fake = FakeSystemLog([entry("Task failed")])
        let reporter = BugReporter(
            environment: LogEnvironment(),
            systemLog: SystemLogOptions(window: 600, source: fake)
        )
        let before = Date()

        let text = try systemLogFile(reporter)

        #expect(text?.contains("Task failed") == true)
        let requested = try #require(fake.requested)
        #expect(abs(requested.timeIntervalSince(before) + 600) < 5)
    }

    @Test func unreadableLogStillProducesAReport() throws {
        let reporter = BugReporter(
            environment: LogEnvironment(),
            systemLog: SystemLogOptions(source: FakeSystemLog(error: StoreClosed()))
        )

        #expect(try systemLogFile(reporter) == "System log unavailable: the store is closed")
    }

    @Test func noSystemLogUnlessAskedFor() throws {
        #expect(try systemLogFile(BugReporter(environment: LogEnvironment())) == nil)
    }

    @Test func osLogLevelsMapOntoLogLevels() {
        #expect(OSLogStoreSource.map(.debug) == .debug)
        #expect(OSLogStoreSource.map(.info) == .info)
        #expect(OSLogStoreSource.map(.notice) == .notice)
        #expect(OSLogStoreSource.map(.undefined) == .notice)
        #expect(OSLogStoreSource.map(.error) == .error)
        #expect(OSLogStoreSource.map(.fault) == .fault)
    }
}
