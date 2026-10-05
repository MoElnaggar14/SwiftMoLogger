import XCTest
@testable import SwiftMoLoggerRemote
import SwiftMoLogger

final class HTTPLogShipperTests: XCTestCase {

    func testShippersAreKeyedByEndpointWithoutCredentials() {
        func shipper(_ endpoint: String) -> HTTPLogShipper {
            HTTPLogShipper(configuration: .init(endpoint: URL(string: endpoint)!))
        }
        let first = shipper("https://logs.example.com/ingest")
        let second = shipper("https://other.example.com/ingest")
        let duplicate = shipper("https://user:secret@logs.example.com/ingest?token=abc")

        XCTAssertNotEqual(first.engineID, second.engineID, "different endpoints must both stay registered")
        XCTAssertEqual(first.engineID, duplicate.engineID, "the same endpoint de-duplicates")
        XCTAssertFalse(duplicate.engineID.contains("secret"))
        XCTAssertFalse(duplicate.engineID.contains("token"))
    }

    func testDefaultJSONBodyEncodesEntries() throws {
        let entries = [
            LogEntry(level: .info, message: "one"),
            LogEntry(level: .warning, message: "two")
        ]
        let data = try HTTPLogShipper.defaultJSONBody(entries)
        let raw = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(raw.contains("\"entries\""))
        XCTAssertTrue(raw.contains("one"))
        XCTAssertTrue(raw.contains("two"))
    }

    func testSentryEnvelopeURLDerivedFromDSN() {
        let dsn = URL(string: "https://abcdef@o123.ingest.sentry.io/456789")!
        let engine = SentryLogEngine(dsn: dsn, release: "1.0", environment: "test")
        XCTAssertEqual(engine.configuration.endpoint.absoluteString, "https://o123.ingest.sentry.io/api/456789/envelope/")
        XCTAssertNotNil(engine.configuration.headers["X-Sentry-Auth"])
    }

    func testDatadogConfiguresAPIKey() {
        let engine = DatadogLogEngine(apiKey: "test-key", site: .eu1, service: "checkout")
        XCTAssertEqual(engine.configuration.headers["DD-API-KEY"], "test-key")
        XCTAssertEqual(engine.configuration.endpoint.host, "http-intake.logs.datadoghq.eu")
    }

    func testLokiSetsBasicAuth() {
        let endpoint = URL(string: "https://loki.example.com/loki/api/v1/push")!
        let engine = LokiLogEngine(endpoint: endpoint, basicAuth: ("user", "pass"))
        XCTAssertTrue(engine.configuration.headers["Authorization"]?.hasPrefix("Basic ") ?? false)
    }
}
