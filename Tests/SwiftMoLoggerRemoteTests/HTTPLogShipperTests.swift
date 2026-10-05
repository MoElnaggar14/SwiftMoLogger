import XCTest
@testable import SwiftMoLoggerRemote
import SwiftMoLogger

final class HTTPLogShipperTests: XCTestCase {

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

    func testSentryEnvelopeURLDerivedFromDSN() throws {
        let dsn = URL(string: "https://abcdef@o123.ingest.sentry.io/456789")!
        let engine = try XCTUnwrap(SentryLogEngine(dsn: dsn, release: "1.0", environment: "test"))
        XCTAssertEqual(engine.configuration.endpoint.absoluteString, "https://o123.ingest.sentry.io/api/456789/envelope/")
        XCTAssertNotNil(engine.configuration.headers["X-Sentry-Auth"])
    }

    func testInvalidSentryDSNIsRejectedInsteadOfCrashing() {
        XCTAssertNil(SentryLogEngine(dsn: URL(string: "ftp://key@o1.ingest.sentry.io/2")!))
        XCTAssertNil(SentryLogEngine(dsn: URL(string: "https://o1.ingest.sentry.io/2")!), "no public key")
        XCTAssertNil(SentryLogEngine(dsn: URL(string: "https://key@o1.ingest.sentry.io")!), "no project")
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
