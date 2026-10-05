import SwiftMoLogger
import SwiftMoLoggerTesting
import Testing

/// Proves the recording queries work with Swift Testing's `#expect`.
@Suite("Recording queries with Swift Testing")
struct SwiftTestingSupportTests {
    @Test func expectFindsWhatWasLogged() {
        let (log, logs) = MoLogger.recording()

        log.error("Payment declined", tag: .api, metadata: ["order_id": "42"])
        log.info("Retrying")

        #expect(logs.contains(.error, containing: "declined", tag: .api))
        #expect(logs.contains(withMetadataKey: "order_id"))
        #expect(logs.count(.error) == 1)
        #expect(logs.count() == 2)
        #expect(!logs.contains(.fault))
    }

    @Test(arguments: [LogLevel.warning, .error, .critical])
    func eachLevelIsMatchedExactly(level: LogLevel) {
        let (log, logs) = MoLogger.recording()

        log.log(level, "Something happened")

        #expect(logs.count(level) == 1)
        #expect(logs.entries(containing: "happened").map(\.level) == [level])
    }
}
