import XCTest
import SwiftMoLogger
@testable import SwiftMoLoggerNetwork
import SwiftMoLoggerTesting

final class NetworkBodyCaptureTests: XCTestCase {
    private func encoder(maxBytes: Int = 1_024) -> NetworkBodyEncoder {
        NetworkBodyEncoder(maxBytes: maxBytes, redactor: Redactor())
    }

    // MARK: - Policy

    func testCaptureIsOffByDefault() async throws {
        let (environment, _) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment)

        let event = try await recordPOST(through: network, in: environment)

        XCTAssertNil(event.requestBody)
        XCTAssertNil(event.responseBody)
        XCTAssertNil(NetworkBodyCapture.off.effectiveLimit)
    }

    func testDebugOnlyCapturesOnlyInDebugBuilds() {
        #if DEBUG
        XCTAssertEqual(NetworkBodyCapture.debugOnly(maxBytes: 100).effectiveLimit, 100)
        #else
        XCTAssertNil(NetworkBodyCapture.debugOnly(maxBytes: 100).effectiveLimit)
        #endif
        XCTAssertEqual(NetworkBodyCapture.always(maxBytes: 100).effectiveLimit, 100)
        XCTAssertNil(NetworkBodyCapture.always(maxBytes: 0).effectiveLimit)
    }

    func testCapturedRequestBodyIsRedactedAndHeadersRecorded() async throws {
        let (environment, recorder) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment, bodies: .always(maxBytes: 4_096))

        let event = try await recordPOST(through: network, in: environment)

        let body = try XCTUnwrap(event.requestBody)
        XCTAssertEqual(body.text, #"{"email":"[EMAIL]","page":2}"#)
        XCTAssertEqual(body.contentType, "application/json")
        XCTAssertFalse(body.isTruncated)
        XCTAssertEqual(event.requestHeaders?["Authorization"], "[REDACTED]")
        XCTAssertEqual(event.requestHeaders?["Content-Type"], "application/json")
        // Bodies stay in the event; log entries never carry them.
        let logged = recorder.recorded().map { "\($0.message) \($0.metadata)" }.joined()
        XCTAssertFalse(logged.contains("email"), logged)
    }

    // MARK: - Encoder

    func testRedactsBodies() {
        let body = encoder().body(
            from: Data(#"{"token":"Bearer abc.def","owner":"jane@example.com"}"#.utf8),
            totalBytes: 54,
            contentType: "application/json; charset=utf-8"
        )

        XCTAssertEqual(body?.text, #"{"token":"Bearer [TOKEN]","owner":"[EMAIL]"}"#)
    }

    func testTruncatesAtMaxBytesWithoutSplittingCharacters() throws {
        let text = String(repeating: "é", count: 10)   // 2 bytes each
        let body = try XCTUnwrap(encoder(maxBytes: 5).body(
            from: Data(text.utf8),
            totalBytes: text.utf8.count,
            contentType: "text/plain"
        ))

        XCTAssertTrue(body.isTruncated)
        XCTAssertEqual(body.text, "éé")
        XCTAssertLessThanOrEqual(body.text.utf8.count, 5)
    }

    func testBodyCutBeforeBufferingIsMarkedTruncated() throws {
        let body = try XCTUnwrap(encoder(maxBytes: 10).body(
            from: Data("short".utf8),
            totalBytes: 1_000_000,
            contentType: "text/plain"
        ))

        XCTAssertTrue(body.isTruncated)
        XCTAssertEqual(body.text, "short")
    }

    func testSecretStraddlingTheLimitIsStillRedacted() throws {
        let text = String(repeating: "a", count: 8) + " jane@example.com"
        let body = try XCTUnwrap(encoder(maxBytes: 12).body(
            from: Data(text.utf8),
            totalBytes: text.utf8.count,
            contentType: "text/plain"
        ))

        XCTAssertFalse(body.text.contains("jane"), body.text)
        XCTAssertTrue(body.isTruncated)
    }

    func testSkipsBinaryContentTypes() {
        let bytes = Data("not really a png".utf8)
        let types = [
            "image/png", "application/octet-stream", "multipart/form-data; boundary=x",
            "application/x-protobuf", "video/mp4"
        ]
        for type in types {
            XCTAssertNil(encoder().body(from: bytes, totalBytes: bytes.count, contentType: type), type)
        }
    }

    func testCapturesTextualContentTypes() {
        let bytes = Data("x=1".utf8)
        let types = [
            "application/json", "application/problem+json", "text/html", "application/xml",
            "application/x-www-form-urlencoded", "application/javascript", "application/graphql",
            "application/vnd.api+json"
        ]
        for type in types {
            XCTAssertNotNil(encoder().body(from: bytes, totalBytes: bytes.count, contentType: type), type)
        }
    }

    func testSniffsBodiesWithoutAContentType() {
        let text = Data("plain words".utf8)
        let binary = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01])
        XCTAssertNotNil(encoder().body(from: text, totalBytes: text.count, contentType: nil))
        XCTAssertNil(encoder().body(from: binary, totalBytes: binary.count, contentType: nil))
        XCTAssertNil(encoder().body(from: Data(), totalBytes: 0, contentType: "text/plain"))
    }

    // MARK: - Response buffering

    func testBuffersResponseChunksUpToTheLimit() throws {
        let network = NetworkLogger(
            logger: MoLogger(registry: EngineRegistry(installDefaultSystemLogger: false)),
            bodies: .always(maxBytes: 4)
        )
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "http://invalid.invalid/")!)

        let chunk = Data(String(repeating: "abcdefgh", count: 200).utf8)
        network.urlSession(session, dataTask: task, didReceive: chunk)
        network.urlSession(session, dataTask: task, didReceive: chunk)

        let body = try XCTUnwrap(network.capturedResponseBody(of: task))
        XCTAssertEqual(body.text, "abcd")
        XCTAssertTrue(body.isTruncated)
        // The buffer is released once the body is taken.
        XCTAssertNil(network.capturedResponseBody(of: task))
    }

    func testBuffersNothingWhenCaptureIsOff() {
        let network = NetworkLogger(logger: MoLogger(registry: EngineRegistry(installDefaultSystemLogger: false)))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: URL(string: "http://invalid.invalid/")!)

        network.urlSession(session, dataTask: task, didReceive: Data("hello".utf8))

        XCTAssertNil(network.capturedResponseBody(of: task))
    }

    // MARK: - cURL

    func testCurlCommandQuotesEveryArgument() {
        let event = NetworkEvent(
            startedAt: Date(),
            endedAt: Date(),
            method: "POST",
            url: URL(string: "https://example.com/a?q=it's&token=REDACTED")!,
            statusCode: 200,
            responseBytes: 0,
            requestBytes: 12,
            requestHeaders: ["Authorization": "[REDACTED]", "Accept": "application/json"],
            requestBody: NetworkBody(text: #"{"name":"O'Brien $HOME `x`"}"#, contentType: "application/json")
        )

        XCTAssertEqual(event.curlCommand, """
        curl \\
          'https://example.com/a?q=it'\\''s&token=REDACTED' \\
          -X 'POST' \\
          -H 'Accept: application/json' \\
          -H 'Authorization: [REDACTED]' \\
          --data-raw '{"name":"O'\\''Brien $HOME `x`"}'
        """)
    }

    func testCurlCommandForAPlainGET() {
        let event = NetworkEvent(
            startedAt: Date(),
            endedAt: Date(),
            method: "GET",
            url: URL(string: "https://example.com/items")!,
            statusCode: 200,
            responseBytes: 0,
            requestBytes: 0
        )

        XCTAssertEqual(event.curlCommand, "curl \\\n  'https://example.com/items'")
    }

    func testCurlCommandFlagsATruncatedBody() {
        let event = NetworkEvent(
            startedAt: Date(),
            endedAt: Date(),
            method: "PUT",
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            responseBytes: 0,
            requestBytes: 99,
            requestBody: NetworkBody(text: "abc", isTruncated: true)
        )

        XCTAssertTrue(event.curlCommand.hasSuffix("--data-raw 'abc' # request body truncated"))
    }

    func testEventsWithoutBodiesStillRoundTrip() throws {
        let event = NetworkEvent(
            startedAt: Date(timeIntervalSince1970: 0),
            endedAt: Date(timeIntervalSince1970: 1),
            method: "GET",
            url: URL(string: "https://example.com")!,
            statusCode: 204,
            responseBytes: 0,
            requestBytes: 0
        )
        let json = try JSONEncoder().encode(event)

        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("requestBody"))
        XCTAssertEqual(try JSONDecoder().decode(NetworkEvent.self, from: json), event)
    }

    // MARK: - Helpers

    /// Sends a JSON POST to a host that never resolves and returns the recorded event.
    private func recordPOST(
        through network: NetworkLogger,
        in environment: LogEnvironment
    ) async throws -> NetworkEvent {
        let session = URLSession(configuration: .ephemeral, delegate: network, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "http://invalid.invalid/users")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer s3cret", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"email":"jane@example.com","page":2}"#.utf8)

        _ = try? await session.data(for: request)

        for _ in 0..<100 where environment.networkEvents.snapshot().isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(environment.networkEvents.snapshot().first)
    }
}
