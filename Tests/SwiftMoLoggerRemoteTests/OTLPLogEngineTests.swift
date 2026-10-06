import XCTest
@testable import SwiftMoLoggerRemote
import SwiftMoLogger

final class OTLPLogEngineTests: XCTestCase {
    private let traceID = "4bf92f3577b34da6a3ce929d0e0e4736"
    private let spanID = "00f067aa0ba902b7"

    private func decode(
        _ entries: [LogEntry],
        resource: [String: String] = ["service.name": "shop"]
    ) throws -> [String: Any] {
        let data = try OTLPLogEngine.makeBody(resource: resource)(entries)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func records(in body: [String: Any]) throws -> [[String: Any]] {
        let resourceLogs = try XCTUnwrap(body["resourceLogs"] as? [[String: Any]])
        let scopeLogs = try XCTUnwrap(resourceLogs.first?["scopeLogs"] as? [[String: Any]])
        return try XCTUnwrap(scopeLogs.first?["logRecords"] as? [[String: Any]])
    }

    private func attributes(_ record: [String: Any]) throws -> [String: [String: Any]] {
        let list = try XCTUnwrap(record["attributes"] as? [[String: Any]])
        var result: [String: [String: Any]] = [:]
        for item in list {
            result[try XCTUnwrap(item["key"] as? String)] = try XCTUnwrap(item["value"] as? [String: Any])
        }
        return result
    }

    func testEnvelopeCarriesResourceAndScope() throws {
        let entries = [LogEntry(level: .info, message: "hi")]
        let body = try decode(entries, resource: ["service.name": "shop", "env": "prod"])
        let resourceLogs = try XCTUnwrap(body["resourceLogs"] as? [[String: Any]])
        let resource = try XCTUnwrap(resourceLogs.first?["resource"] as? [String: Any])
        let keys = (resource["attributes"] as? [[String: Any]])?.compactMap { $0["key"] as? String }
        XCTAssertEqual(keys, ["env", "service.name"])
        let scope = (resourceLogs.first?["scopeLogs"] as? [[String: Any]])?.first?["scope"] as? [String: Any]
        XCTAssertEqual(scope?["name"] as? String, "SwiftMoLogger")
    }

    func testEngineAddsServiceAndSDKResourceAttributes() {
        let engine = OTLPLogEngine(
            endpoint: URL(string: "https://otel.example.com:4318/v1/logs")!,
            serviceName: "shop-ios",
            headers: ["Authorization": "Bearer token"]
        )
        XCTAssertEqual(engine.configuration.headers["Content-Type"], "application/json")
        XCTAssertEqual(engine.configuration.headers["Authorization"], "Bearer token")
        XCTAssertTrue(engine.engineID.hasPrefix("swiftmologger.remote.otlp."))
        XCTAssertFalse(engine.engineID.contains("token"))
    }

    func testRecordMapsTimeSeverityAndBody() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000.5)
        let entry = LogEntry(timestamp: timestamp, level: .warning, message: "slow")
        let record = try XCTUnwrap(records(in: decode([entry])).first)

        XCTAssertEqual(record["timeUnixNano"] as? String, "1700000000500000000")
        XCTAssertEqual(record["severityNumber"] as? Int, 13)
        XCTAssertEqual(record["severityText"] as? String, "WARN")
        XCTAssertEqual((record["body"] as? [String: Any])?["stringValue"] as? String, "slow")
        XCTAssertNil(record["traceId"])
    }

    func testSeverityNumbersFollowOpenTelemetry() {
        let expected: [LogLevel: Int] = [
            .trace: 1, .debug: 5, .info: 9, .notice: 10, .warning: 13, .error: 17, .critical: 21, .fault: 22
        ]
        for level in LogLevel.allCases {
            XCTAssertEqual(OTLPLogEngine.severityNumber(level), expected[level], "\(level)")
        }
    }

    func testTraceContextMetadataBecomesTraceAndSpanIDs() throws {
        let entry = LogEntry(level: .error, message: "failed", metadata: [
            "trace.id": .string(traceID), "span.id": .string(spanID), "trace.sampled": .bool(true), "order": "42"
        ])
        let record = try XCTUnwrap(records(in: decode([entry])).first)

        XCTAssertEqual(record["traceId"] as? String, traceID)
        XCTAssertEqual(record["spanId"] as? String, spanID)
        XCTAssertEqual(record["flags"] as? Int, 1)
        let attributes = try attributes(record)
        XCTAssertNil(attributes["trace.id"], "trace fields aren't duplicated as attributes")
        XCTAssertEqual(attributes["order"]?["stringValue"] as? String, "42")
    }

    func testMalformedTraceIDIsNotExported() throws {
        let entry = LogEntry(level: .info, message: "x", metadata: ["trace.id": "not-a-trace"])
        let record = try XCTUnwrap(records(in: decode([entry])).first)
        XCTAssertNil(record["traceId"])
    }

    func testAttributesCoverTagSourceThreadAndEveryValueType() throws {
        let entry = LogEntry(
            level: .info,
            message: "paid",
            tag: .api,
            metadata: [
                "count": .int(3),
                "ratio": .double(0.5),
                "ok": .bool(true),
                "ids": .array(["a", "b"]),
                "card": .dictionary(["brand": "visa"]),
                "none": .null
            ],
            source: SourceLocation(file: "Shop/Checkout.swift", function: "pay()", line: 12, column: 1),
            threadName: "main"
        )
        let attributes = try attributes(XCTUnwrap(records(in: decode([entry])).first))

        XCTAssertEqual(attributes["count"]?["intValue"] as? String, "3")
        XCTAssertEqual(attributes["ratio"]?["doubleValue"] as? Double, 0.5)
        XCTAssertEqual(attributes["ok"]?["boolValue"] as? Bool, true)
        XCTAssertEqual(((attributes["ids"]?["arrayValue"] as? [String: Any])?["values"] as? [Any])?.count, 2)
        XCTAssertNotNil(attributes["card"]?["kvlistValue"])
        XCTAssertEqual(attributes["none"]?.isEmpty, true)
        XCTAssertEqual(attributes["swiftmologger.tag"]?["stringValue"] as? String, LogTag.api.rawValue)
        XCTAssertEqual(attributes["code.file.path"]?["stringValue"] as? String, "Shop/Checkout.swift")
        XCTAssertEqual(attributes["code.function.name"]?["stringValue"] as? String, "pay()")
        XCTAssertEqual(attributes["code.line.number"]?["intValue"] as? String, "12")
        XCTAssertEqual(attributes["thread.name"]?["stringValue"] as? String, "main")
    }
}
