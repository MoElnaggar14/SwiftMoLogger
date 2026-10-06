import Foundation
import SwiftMoLogger
import SwiftMoLoggerTesting
import Testing

@Suite("Swift task names")
struct TaskNameTests {
    @Test func entriesOutsideANamedTaskHaveNoTaskName() {
        let (log, logs) = MoLogger.recording()
        log.info("plain")
        #expect(logs.recorded().first?.taskName == nil)
    }

    #if compiler(>=6.2)
    @Test func entriesRecordTheNamedTaskTheyWereLoggedIn() async throws {
        guard #available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *) else { return }
        let (log, logs) = MoLogger.recording()

        await Task(name: "checkout.pay") { log.info("paying") }.value

        #expect(logs.recorded().first?.taskName == "checkout.pay")
    }
    #endif

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        return encoder
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return decoder
    }

    @Test func entriesWrittenBy40StillDecode() throws {
        // A 4.0 entry is today's encoding without the taskName key.
        let current = LogEntry(level: .info, message: "hello", taskName: "sync")
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(current)) as? [String: Any])
        #expect(object.removeValue(forKey: "taskName") as? String == "sync")
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let entry = try decoder.decode(LogEntry.self, from: legacy)

        #expect(entry.taskName == nil)
        #expect(entry.message == "hello")
    }

    @Test func taskNameRoundTripsThroughJSON() throws {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000.5), level: .info, message: "hi", taskName: "sync"
        )
        let decoded = try decoder.decode(LogEntry.self, from: encoder.encode(entry))
        #expect(decoded == entry)
    }

    @Test func entriesWithoutATaskNameOmitTheKey() throws {
        let data = try encoder.encode(LogEntry(level: .info, message: "hi", taskName: nil))
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("taskName"))
    }

    @Test func redactionKeepsTheTaskName() {
        let logs = RecordingLogEngine()
        let redacting = RedactingLogEngine(wrapping: logs)
        redacting.log(LogEntry(level: .info, message: "mail jane@example.com", taskName: "import"))
        #expect(logs.recorded().first?.taskName == "import")
        #expect(logs.recorded().first?.message.contains("jane@example.com") == false)
    }
}
