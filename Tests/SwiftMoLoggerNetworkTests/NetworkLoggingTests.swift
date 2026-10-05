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

    func testUntaggedLoggerGetsAPITag() throws {
        let (environment, recorder) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment)
        let session = URLSession(configuration: .ephemeral, delegate: network, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        // A request to an invalid host fails fast without leaving the machine.
        let task = session.dataTask(with: URL(string: "http://invalid.invalid/")!)
        let done = expectation(description: "completed")
        let observation = task.observe(\.state) { task, _ in
            if task.state == .completed { done.fulfill() }
        }
        task.resume()
        wait(for: [done], timeout: 30)
        observation.invalidate()

        // Delegate callbacks run on the session's queue; give them a moment to land.
        let deadline = Date().addingTimeInterval(5)
        while recorder.recorded().filter({ $0.message.hasPrefix("HTTP") }).count < 2, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let messages = recorder.recorded().filter { $0.message.hasPrefix("HTTP") }
        XCTAssertEqual(messages.first?.message, "HTTP request")
        XCTAssertEqual(messages.first?.tag, .api)
        XCTAssertTrue(messages.contains { $0.message == "HTTP failure" })
        XCTAssertEqual(environment.networkEvents.snapshot().count, 1)
        XCTAssertFalse(environment.breadcrumbs.snapshot().isEmpty)
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
