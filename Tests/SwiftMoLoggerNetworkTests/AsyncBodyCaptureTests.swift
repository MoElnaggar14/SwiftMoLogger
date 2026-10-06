import XCTest
import SwiftMoLogger
@testable import SwiftMoLoggerNetwork
import SwiftMoLoggerTesting

final class AsyncBodyCaptureTests: XCTestCase {
    func testCapturesTheResponseBodyOfAnAsyncRequest() async throws {
        let (environment, recorder) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment, bodies: .always(maxBytes: 4_096))

        let (data, response) = try await send(path: "/user", through: network)
        let event = try await recordedEvent(in: environment)

        // The caller gets the response untouched.
        XCTAssertEqual(String(decoding: data, as: UTF8.self), StubURLProtocol.userJSON)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let body = try XCTUnwrap(event.responseBody)
        XCTAssertEqual(body.text, #"{"name":"Jane","email":"[EMAIL]"}"#)
        XCTAssertEqual(body.contentType, "application/json")
        XCTAssertFalse(body.isTruncated)
        XCTAssertEqual(event.statusCode, 200)
        // Bodies stay in the event; log entries never carry them.
        let logged = recorder.recorded().map { "\($0.message) \($0.metadata)" }.joined()
        XCTAssertFalse(logged.contains("email"), logged)
        XCTAssertFalse(logged.contains("Jane"), logged)
    }

    func testTruncatesAsyncResponseBodiesAtMaxBytes() async throws {
        let (environment, _) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment, bodies: .always(maxBytes: 16))

        _ = try await send(path: "/large", through: network)
        let event = try await recordedEvent(in: environment)

        let body = try XCTUnwrap(event.responseBody)
        XCTAssertEqual(body.text, String(repeating: "a", count: 16))
        XCTAssertTrue(body.isTruncated)
    }

    func testSkipsBinaryAsyncResponseBodies() async throws {
        let (environment, _) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment, bodies: .always(maxBytes: 4_096))

        _ = try await send(path: "/image", through: network)
        let event = try await recordedEvent(in: environment)

        XCTAssertNil(event.responseBody)
        XCTAssertEqual(event.statusCode, 200)
    }

    func testCapturesNothingWhenCaptureIsOff() async throws {
        let (environment, _) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment)

        let (data, _) = try await send(path: "/user", through: network)
        let event = try await recordedEvent(in: environment)

        XCTAssertFalse(data.isEmpty)
        XCTAssertNil(event.requestBody)
        XCTAssertNil(event.responseBody)
    }

    func testUploadCapturesBothBodies() async throws {
        let (environment, _) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment, bodies: .always(maxBytes: 4_096))
        let session = Self.stubSession()
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: URL(string: "https://stub.example/user")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await network.upload(
            for: request,
            from: Data(#"{"email":"jane@example.com"}"#.utf8),
            on: session
        )
        let event = try await recordedEvent(in: environment)

        XCTAssertEqual(event.method, "POST")
        XCTAssertEqual(event.requestBody?.text, #"{"email":"[EMAIL]"}"#)
        XCTAssertEqual(event.responseBody?.text, #"{"name":"Jane","email":"[EMAIL]"}"#)
    }

    func testFailedAsyncRequestStillRecordsOneEvent() async throws {
        let (environment, _) = LogEnvironment.recording()
        let network = NetworkLogger(environment: environment, bodies: .always(maxBytes: 4_096))

        do {
            _ = try await send(path: "/fail", through: network)
            XCTFail("Expected the request to fail")
        } catch {
            // Expected: the stub refuses the connection.
        }
        let event = try await recordedEvent(in: environment)

        XCTAssertNotNil(event.errorDescription)
        XCTAssertNil(event.responseBody)
        XCTAssertEqual(environment.networkEvents.snapshot().count, 1)
    }

    // MARK: - Helpers

    private static func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func send(path: String, through network: NetworkLogger) async throws -> (Data, URLResponse) {
        let session = Self.stubSession()
        defer { session.finishTasksAndInvalidate() }
        let request = URLRequest(url: URL(string: "https://stub.example\(path)")!)
        return try await network.data(for: request, on: session)
    }

    /// Waits for the request's event; metrics can land just after the call returns.
    private func recordedEvent(in environment: LogEnvironment) async throws -> NetworkEvent {
        for _ in 0..<100 where environment.networkEvents.snapshot().isEmpty {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return try XCTUnwrap(environment.networkEvents.snapshot().first)
    }
}

/// Serves canned responses for `https://stub.example/…` without touching the network.
final class StubURLProtocol: URLProtocol {
    static let userJSON = #"{"name":"Jane","email":"jane@example.com"}"#

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "stub.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let body: Data
        let contentType: String
        switch path {
        case "/user":
            body = Data(Self.userJSON.utf8)
            contentType = "application/json"
        case "/large":
            body = Data(String(repeating: "a", count: 10_000).utf8)
            contentType = "text/plain"
        case "/image":
            body = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02])
            contentType = "image/png"
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        guard let url = request.url, let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
