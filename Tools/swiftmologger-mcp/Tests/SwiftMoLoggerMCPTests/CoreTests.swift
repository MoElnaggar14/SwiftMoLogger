import Foundation
import SwiftMoLogger
import Testing
@testable import SwiftMoLoggerMCPCore

@Suite("LiveSink line protocol")
struct WireLineTests {
    @Test func decodesVersion2Hello() {
        guard case let .hello(hello) = WireLine.decode(Wire.hello()) else {
            Issue.record("expected a hello line")
            return
        }
        #expect(hello.version == 2)
        #expect(hello.app == "com.acme.shop")
        #expect(hello.appVersion == "1.4.2")
    }

    @Test func decodesThe3xBannerAsVersion1() throws {
        let banner = try JSONSerialization.data(withJSONObject: [
            "service": "SwiftMoLogger.LiveSink", "version": 1, "app": "com.acme.shop", "started_at": "2026-01-01T00:00:00Z"
        ])
        guard case let .hello(hello) = WireLine.decode(banner) else {
            Issue.record("expected a hello line")
            return
        }
        #expect(hello.version == 1)
    }

    @Test func decodesAnEntryEncodedLikeLiveSink() {
        // LiveSink encodes milliseconds, so use a timestamp that survives the round trip exactly.
        let entry = Wire.entry("Payment failed", level: .error, tag: .api, metadata: ["code": 402],
                               at: Date(timeIntervalSince1970: 1_790_000_000.125))
        #expect(WireLine.decode(Wire.line(entry)) == .entry(entry))
    }

    @Test func skipsUnknownControlLinesAndGarbage() throws {
        let control = try JSONSerialization.data(withJSONObject: ["kind": "breadcrumb", "message": "tapped"])
        #expect(WireLine.decode(control) == .unknownControl(kind: "breadcrumb"))
        #expect(WireLine.decode(Data("not json".utf8)) == .invalid)
    }

    @Test func splitsLinesAcrossChunks() {
        var splitter = LineSplitter()
        #expect(splitter.append(Data("{\"a\":1}\n{\"b\"".utf8)).count == 1)
        #expect(splitter.append(Data(":2}\n\n".utf8)) == [Data("{\"b\":2}".utf8)])
    }
}

@Suite("Ring buffer")
struct RingBufferTests {
    @Test func dropsTheOldestAndKeepsOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        (1...5).forEach { buffer.append($0) }
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.count == 3)
    }
}

@Suite("Queries")
struct LogQueryTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func stored(_ entry: LogEntry, seq: UInt64 = 1, device: String = "com.acme.shop") -> StoredEntry {
        StoredEntry(seq: seq, device: device, session: 1, receivedAt: now, entry: entry)
    }

    @Test func filtersByLevelDeviceAndSequence() {
        let warning = stored(Wire.entry("slow", level: .warning), seq: 5)
        #expect(LogQuery(minLevel: .warning).matches(warning))
        #expect(!LogQuery(minLevel: .error).matches(warning))
        #expect(!LogQuery(device: "other").matches(warning))
        #expect(!LogQuery(afterSeq: 5).matches(warning))
        #expect(LogQuery(afterSeq: 4).matches(warning))
    }

    @Test func matchesTagsByDomainPrefixOrName() {
        let database = stored(Wire.entry("query", tag: .database))
        #expect(LogQuery(tags: ["data"]).matches(database))
        #expect(LogQuery(tags: ["DATABASE"]).matches(database))
        #expect(!LogQuery(tags: ["network"]).matches(database))
        #expect(!LogQuery(tags: ["data"]).matches(stored(Wire.entry("untagged"))))
    }

    @Test func matchesTextInMessageOrMetadata() {
        let entry = stored(Wire.entry("Payment failed", metadata: ["order_id": "ord_4291"]))
        #expect(LogQuery(text: "payment").matches(entry))
        #expect(LogQuery(text: "ORD_4291").matches(entry))
        #expect(LogQuery(text: "regex:pay.*fail").matches(entry))
        #expect(!LogQuery(text: "refund").matches(entry))
    }

    @Test func parsesRelativeAndAbsoluteTimes() {
        #expect(TimeExpression.date(from: "90s", now: now) == now.addingTimeInterval(-90))
        #expect(TimeExpression.date(from: "5m", now: now) == now.addingTimeInterval(-300))
        #expect(TimeExpression.date(from: "2h", now: now) == now.addingTimeInterval(-7_200))
        #expect(TimeExpression.date(from: "2026-10-05T14:00:00Z") != nil)
        #expect(TimeExpression.date(from: "soon") == nil)
    }

    @Test func parsesLevelNames() {
        #expect(LogLevel(name: "warn") == .warning)
        #expect(LogLevel(name: "ERROR") == .error)
        #expect(LogLevel(name: "loud") == nil)
    }
}
