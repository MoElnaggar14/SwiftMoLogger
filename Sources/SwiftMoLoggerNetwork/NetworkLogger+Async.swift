import Foundation
import SwiftMoLogger

public extension NetworkLogger {
    /// Sends `request` with `session.data(for:delegate:)` and logs it, capturing
    /// the response body the call returns.
    ///
    /// The `async` URLSession APIs never hand response bytes to a delegate, so
    /// passing the logger as `delegate:` captures only the request body. Use this
    /// instead when body capture is on and you want responses in the Diagnostics Hub:
    ///
    /// ```swift
    /// let (data, response) = try await network.data(for: request, on: session)
    /// ```
    ///
    /// It behaves like `session.data(for:delegate:)` with the logger as the task
    /// delegate: same result, same errors, and the request isn't changed. The
    /// returned body goes through the same redaction, `maxBytes` limit and
    /// text-only filter as other captured bodies, and is kept in the
    /// ``NetworkEvent`` only. When capture is off it's a plain
    /// `session.data(for: request, delegate: self)`.
    ///
    /// - Parameters:
    ///   - request: The request to send.
    ///   - session: The session to send it on. Its own delegate still gets session-level callbacks.
    func data(for request: URLRequest, on session: URLSession) async throws -> (Data, URLResponse) {
        guard bodyEncoder != nil, events != nil else {
            return try await session.data(for: request, delegate: self)
        }
        let capture = AsyncBodyCapture(network: self, requestBody: nil)
        do {
            let (data, response) = try await session.data(for: request, delegate: capture)
            capture.finish(responseData: data, response: response)
            return (data, response)
        } catch {
            capture.finish(responseData: nil, response: nil)
            throw error
        }
    }

    /// Sends `request` with `session.upload(for:from:delegate:)` and logs it,
    /// capturing `bodyData` as the request body and the response body the call
    /// returns. See ``data(for:on:)``.
    ///
    /// - Parameters:
    ///   - request: The request to send. Its `httpBody` is ignored, as URLSession ignores it.
    ///   - bodyData: The body to upload.
    ///   - session: The session to send it on.
    func upload(
        for request: URLRequest,
        from bodyData: Data,
        on session: URLSession
    ) async throws -> (Data, URLResponse) {
        guard bodyEncoder != nil, events != nil else {
            return try await session.upload(for: request, from: bodyData, delegate: self)
        }
        let capture = AsyncBodyCapture(network: self, requestBody: bodyData)
        do {
            let (data, response) = try await session.upload(for: request, from: bodyData, delegate: capture)
            capture.finish(responseData: data, response: response)
            return (data, response)
        } catch {
            capture.finish(responseData: nil, response: nil)
            throw error
        }
    }
}

/// The task delegate for one ``NetworkLogger/data(for:on:)`` call.
///
/// URLSession may deliver the task's metrics before or after the `async` call
/// returns, so the event is recorded by whichever comes second: the metrics
/// (which produce the event) or the returned body.
///
/// `@unchecked Sendable` is safe because `network` and `requestBody` are
/// immutable `Sendable` values, and the mutable state is only touched under `lock`.
final class AsyncBodyCapture: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let network: NetworkLogger
    private let requestBody: Data?
    private let lock = UnfairLock()
    private var pendingEvent: NetworkEvent?
    private var responseBody: NetworkBody?
    private var bodyArrived = false

    init(network: NetworkLogger, requestBody: Data?) {
        self.network = network
        self.requestBody = requestBody
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        guard let event = network.logOutcome(of: task, metrics: metrics, requestBody: requestBody) else { return }
        let ready: NetworkEvent? = lock.withLock {
            guard bodyArrived else {
                pendingEvent = event
                return nil
            }
            return event.replacingResponseBody(with: responseBody)
        }
        if let ready { network.events?.record(ready) }
    }

    /// Hands over what the `async` call returned: `nil` data when it threw.
    func finish(responseData: Data?, response: URLResponse?) {
        let body = responseData.flatMap { data in
            network.bodyEncoder?.body(
                from: data,
                totalBytes: data.count,
                contentType: NetworkLogger.contentType(of: response)
            )
        }
        let ready: NetworkEvent? = lock.withLock {
            bodyArrived = true
            responseBody = body
            guard let event = pendingEvent else { return nil }
            pendingEvent = nil
            return event.replacingResponseBody(with: body)
        }
        if let ready { network.events?.record(ready) }
    }
}

extension NetworkEvent {
    /// A copy with `body` as its response body, keeping the current one when `body` is `nil`.
    func replacingResponseBody(with body: NetworkBody?) -> NetworkEvent {
        guard let body else { return self }
        return NetworkEvent(
            id: id,
            startedAt: startedAt,
            endedAt: endedAt,
            method: method,
            url: url,
            statusCode: statusCode,
            responseBytes: responseBytes,
            requestBytes: requestBytes,
            errorDescription: errorDescription,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseBody: body
        )
    }
}
