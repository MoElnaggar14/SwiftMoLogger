import XCTest
import SwiftMoLogger
@testable import SwiftMoLoggerNetwork
import SwiftMoLoggerTesting

final class NetworkLoggingTests: XCTestCase {
    func testRedactsSensitiveHeadersCaseInsensitively() {
        let logger = NetworkLogger(
            logger: MoLogger(registry: EngineRegistry(installDefaultSystemLogger: false)),
            sensitiveHeaders: ["Authorization"]
        )

        let rendered = logger.redactedHeaders(["authorization": "Bearer s3cret", "Accept": "json"])

        XCTAssertFalse(rendered.contains("s3cret"))
        XCTAssertTrue(rendered.contains("authorization=[REDACTED]"))
        XCTAssertTrue(rendered.contains("Accept=json"))
    }

    func testDefaultSensitiveHeaders() {
        XCTAssertTrue(NetworkLogger.defaultSensitiveHeaders.isSuperset(of: ["authorization", "cookie", "x-api-key"]))
    }

    func testUntaggedLoggerGetsAPITag() async throws {
        let (environment, recorder) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment)
        let session = URLSession(configuration: .ephemeral, delegate: network, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        // The .invalid TLD never resolves, so this fails fast without leaving the machine.
        _ = try? await session.data(from: URL(string: "http://invalid.invalid/")!)

        // Delegate callbacks run on the session's queue; give the last ones a moment to land.
        for _ in 0..<100 where recorder.recorded().filter({ $0.message.hasPrefix("HTTP") }).count < 2 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let messages = recorder.recorded().filter { $0.message.hasPrefix("HTTP") }
        XCTAssertEqual(messages.first?.message, "HTTP request")
        XCTAssertEqual(messages.first?.tag, .api)
        XCTAssertTrue(messages.contains { $0.message == "HTTP failure" })
        XCTAssertEqual(environment.networkEvents.snapshot().count, 1)
        XCTAssertFalse(environment.breadcrumbs.snapshot().isEmpty)
    }

    func testPerTaskDelegateStillLogsTheRequest() async throws {
        let (environment, recorder) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment)
        // No session delegate: only the per-task delegate sees the task.
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        _ = try? await session.data(from: URL(string: "http://invalid.invalid/")!, delegate: network)

        for _ in 0..<100 where recorder.recorded().filter({ $0.message.hasPrefix("HTTP") }).count < 2 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let messages = recorder.recorded().map(\.message).filter { $0.hasPrefix("HTTP") }
        XCTAssertEqual(messages, ["HTTP request", "HTTP failure"])
    }

    func testDefaultRedactionHidesSensitiveQueryValuesAndCredentials() {
        let url = URL(string: "https://user:pw@example.com/cb?code=abc123&page=2&Access_Token=t0k#frag")!

        let redacted = URLRedaction.default.apply(to: url).absoluteString

        XCTAssertEqual(redacted, "https://example.com/cb?code=REDACTED&page=2&Access_Token=REDACTED#frag")
    }

    func testRedactionPolicies() {
        let url = URL(string: "https://example.com/a?x=1&key=k#f")!
        XCTAssertEqual(URLRedaction.full.apply(to: url), url)
        XCTAssertEqual(URLRedaction.withoutQuery.apply(to: url).absoluteString, "https://example.com/a")
        XCTAssertEqual(
            URLRedaction.redactingQueryItems(["X"]).apply(to: url).absoluteString,
            "https://example.com/a?x=REDACTED&key=k#f"
        )
        let plain = URL(string: "https://example.com/a")!
        XCTAssertEqual(URLRedaction.default.apply(to: plain), plain)
    }

    func testSecretsInTheURLNeverReachLogsBreadcrumbsOrEvents() async throws {
        let (environment, recorder) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment)
        let session = URLSession(configuration: .ephemeral, delegate: network, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        _ = try? await session.data(from: URL(string: "http://invalid.invalid/cb?token=s3cret&page=2")!)

        for _ in 0..<100 where recorder.recorded().filter({ $0.message.hasPrefix("HTTP") }).count < 2 {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let entries = recorder.recorded().filter { $0.message.hasPrefix("HTTP") }
        XCTAssertEqual(entries.count, 2)
        // The failure's error carries the failing URL in its userInfo; it must not leak either.
        let logged = entries.map { "\($0.message) \($0.metadata)" }.joined()
            + environment.breadcrumbs.snapshot().map(\.message).joined()
            + environment.networkEvents.snapshot().map { "\($0.url) \($0.errorDescription ?? "")" }.joined()
        XCTAssertFalse(logged.contains("s3cret"), logged)
        XCTAssertTrue(logged.contains("token=REDACTED"))
        XCTAssertTrue(logged.contains("page=2"))
    }

    func testTraceparentHeaderOnlyInsideATrace() {
        var outside = URLRequest(url: URL(string: "https://example.com")!)
        outside.addTraceparentHeader()
        XCTAssertNil(outside.value(forHTTPHeaderField: "traceparent"))

        let trace = TraceContext.generate()
        trace.run {
            var inside = URLRequest(url: URL(string: "https://example.com")!)
            inside.addTraceparentHeader()
            let header = inside.value(forHTTPHeaderField: "traceparent")
            XCTAssertEqual(header.flatMap(TraceContext.parse(traceparent:))?.traceID, trace.traceID)
        }
    }
}
