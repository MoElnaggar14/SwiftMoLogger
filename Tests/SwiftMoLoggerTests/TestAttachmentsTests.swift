import Foundation
import SwiftMoLogger
@testable import SwiftMoLoggerTesting
import Testing

@Suite("Recorded logs as test attachments")
struct TestAttachmentsTests {
    @Test func textHasOneLinePerEntryWithLevelTagMetadataAndSource() {
        let logs = RecordingLogEngine()
        logs.log(LogEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000.5),
            level: .error,
            message: "Payment declined",
            tag: .api,
            metadata: ["order_id": "42", "amount": .int(5)],
            source: SwiftMoLogger.SourceLocation(file: "Shop/Checkout.swift", function: "pay()", line: 12, column: 1)
        ))
        logs.log(LogEntry(level: .info, message: "Retrying"))

        let lines = logs.attachmentText().split(separator: "\n").map(String.init)

        #expect(lines.count == 2)
        #expect(lines[0] == "2023-11-14T22:13:20.500Z ERROR \(LogTag.api.rawValue) Payment declined "
            + "{amount=5 order_id=42} (Shop/Checkout.swift:12)")
        #expect(lines[1].contains(" INFO Retrying ("))
    }

    @Test func emptyRecorderGivesEmptyText() {
        #expect(RecordingLogEngine().attachmentText().isEmpty)
    }

    #if compiler(>=6.2)
    @Test func attachRecordsWithoutAffectingTheEntries() {
        let (log, logs) = MoLogger.recording()
        log.warning("slow response", tag: .api)

        logs.attach(named: "checkout-logs")

        #expect(logs.count() == 1)
    }
    #endif
}
