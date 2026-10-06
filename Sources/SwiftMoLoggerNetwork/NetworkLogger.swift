import Foundation
import SwiftMoLogger

/// Logs `URLSession` traffic as a session or task delegate.
///
/// Inject it where you create sessions; there is no global hook:
///
/// ```swift
/// let network = NetworkLogger(environment: logging)
///
/// // Every task on a session you own:
/// let session = URLSession(configuration: .default, delegate: network, delegateQueue: nil)
///
/// // Or a single request on any session, including `URLSession.shared`:
/// let (data, _) = try await URLSession.shared.data(for: request, delegate: network)
/// ```
///
/// For each task it logs the request (with sensitive headers and URL query
/// values redacted, see ``URLRedaction``) and the outcome (status, bytes, duration), leaves breadcrumbs, and records a
/// ``NetworkEvent`` for the Diagnostics Hub's waterfall. It only observes: it
/// never changes requests or affects redirects.
///
/// Bodies aren't captured unless you pass `bodies:` (see ``NetworkBodyCapture``).
/// Request bodies come from `URLRequest.httpBody`. Response bodies come from
/// `urlSession(_:dataTask:didReceive:)`, which URLSession calls only for data
/// tasks created without a completion handler on a session whose delegate is
/// this logger; the `async` and completion-handler APIs keep the data to
/// themselves. For `async` code, send the request through the logger's
/// ``data(for:on:)`` or ``upload(for:from:on:)`` instead, which capture the
/// bodies they return. If your app has its own data delegate, forward that
/// callback here.
///
/// To connect requests to a backend trace, call `request.addTraceparentHeader()`
/// inside `TraceContext.run { … }`.
public final class NetworkLogger: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    /// Header names (lower-case) whose values are never logged.
    public static let defaultSensitiveHeaders: Set<String> = [
        "authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token", "proxy-authorization"
    ]

    private let logger: MoLogger
    let events: NetworkEventStore?
    private let breadcrumbs: BreadcrumbStore?
    private let sensitiveHeaders: Set<String>
    private let urlRedaction: URLRedaction
    /// `nil` when body capture is off for this build.
    let bodyEncoder: NetworkBodyEncoder?

    /// Tasks whose request was already logged by `didCreateTask`. That callback
    /// only reaches session-level delegates, so tasks using a per-task delegate
    /// (`session.data(for:delegate:)`) get their request logged with the outcome.
    ///
    /// `@unchecked Sendable` is safe because every other stored property is an
    /// immutable `Sendable` value, and these two are only touched under `lock`.
    private let lock = UnfairLock()
    private var announcedTasks: Set<ObjectIdentifier> = []
    /// Response bytes received so far, per data task, while body capture is on.
    private var responseBuffers: [ObjectIdentifier: ResponseBodyBuffer] = [:]

    /// - Parameters:
    ///   - logger: Receives request and response entries. Untagged entries get `.api`.
    ///   - events: Records each task for the Diagnostics Hub. `nil` to skip.
    ///   - breadcrumbs: Gets a breadcrumb per request and response. `nil` to skip.
    ///   - sensitiveHeaders: Header names (any case) whose values are redacted.
    ///   - urlRedaction: How much of each URL is written to logs, breadcrumbs and events.
    ///   - bodies: Whether request and response bodies are captured into events. Off by default.
    ///   - redactor: Scrubs captured bodies before they're stored.
    public init( // swiftlint:disable:this function_parameter_count
        logger: MoLogger,
        events: NetworkEventStore? = nil,
        breadcrumbs: BreadcrumbStore? = nil,
        sensitiveHeaders: Set<String> = NetworkLogger.defaultSensitiveHeaders,
        urlRedaction: URLRedaction = .default,
        bodies: NetworkBodyCapture = .off,
        redactor: Redactor = Redactor()
    ) {
        self.logger = logger.tag == nil ? logger.with(tag: .api) : logger
        self.events = events
        self.breadcrumbs = breadcrumbs
        self.sensitiveHeaders = Set(sensitiveHeaders.map { $0.lowercased() })
        self.urlRedaction = urlRedaction
        self.bodyEncoder = bodies.effectiveLimit.map { NetworkBodyEncoder(maxBytes: $0, redactor: redactor) }
    }

    /// Logs through the environment's logger and records into its stores.
    public convenience init(
        environment: LogEnvironment,
        urlRedaction: URLRedaction = .default,
        bodies: NetworkBodyCapture = .off,
        redactor: Redactor = Redactor()
    ) {
        self.init(
            logger: environment.logger,
            events: environment.networkEvents,
            breadcrumbs: environment.breadcrumbs,
            urlRedaction: urlRedaction,
            bodies: bodies,
            redactor: redactor
        )
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { _ = announcedTasks.insert(ObjectIdentifier(task)) }
        logRequest(of: task)
    }

    private func logRequest(of task: URLSessionTask) {
        guard let request = task.originalRequest ?? task.currentRequest else { return }
        let url = request.url.map { urlRedaction.apply(to: $0).absoluteString } ?? "?"
        logger.info("HTTP request", metadata: [
            "http.method": .string(request.httpMethod ?? "GET"),
            "http.url": .string(url),
            "http.headers": .string(redactedHeaders(request.allHTTPHeaderFields ?? [:])),
            "http.body_bytes": .int(Int64(request.httpBody?.count ?? 0))
        ])
        breadcrumbs?.record("→ \(request.httpMethod ?? "GET") \(url)", category: .network)
    }

    /// Logs the outcome. URLSession delivers metrics for every task, including
    /// those created with the async and completion-handler APIs, which never
    /// reach the session delegate's `didCompleteWithError`. By the time
    /// metrics arrive the task has finished, so its response and error are final.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        if let event = logOutcome(of: task, metrics: metrics) {
            events?.record(event)
        }
    }

    /// Logs the task's outcome and returns its event, or `nil` when there's no
    /// event store. `requestBody` stands in for `httpBody` (an upload's data).
    func logOutcome(
        of task: URLSessionTask,
        metrics: URLSessionTaskMetrics,
        requestBody: Data? = nil
    ) -> NetworkEvent? {
        let announced = lock.withLock { announcedTasks.remove(ObjectIdentifier(task)) != nil }
        if !announced { logRequest(of: task) }

        let error = task.error
        let request = task.originalRequest
        let url = urlRedaction.apply(to: task.response?.url ?? request?.url ?? URL(fileURLWithPath: "/"))
        let method = request?.httpMethod ?? "GET"
        let interval = metrics.taskInterval
        let durationMS = interval.duration * 1_000
        let transaction = metrics.transactionMetrics.last
        let responseBytes = transaction?.countOfResponseBodyBytesReceived ?? task.countOfBytesReceived
        let requestBytes = transaction?.countOfRequestBodyBytesSent ?? task.countOfBytesSent
        let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0

        if let error {
            logger.error("HTTP failure", metadata: [
                "http.method": .string(method),
                "http.url": .string(url.absoluteString),
                "http.duration_ms": .double(durationMS),
                "error": .string(Self.describe(error))
            ])
            breadcrumbs?.record("✗ \(url.host ?? "?"): \(error.localizedDescription)", category: .network)
        } else {
            let level: LogLevel = status >= 500 ? .error : (status >= 400 ? .warning : .info)
            logger.log(level, "HTTP response", metadata: [
                "http.method": .string(method),
                "http.url": .string(url.absoluteString),
                "http.status": .int(Int64(status)),
                "http.response_bytes": .int(responseBytes),
                "http.duration_ms": .double(durationMS)
            ])
            breadcrumbs?.record("← \(status) \(url.lastPathComponent) (\(Int(durationMS))ms)", category: .network)
        }

        guard events != nil else {
            // Release any buffered bytes; there's nowhere to put them.
            if bodyEncoder != nil { _ = capturedResponseBody(of: task) }
            return nil
        }
        return NetworkEvent(
            startedAt: interval.start,
            endedAt: interval.end,
            method: method,
            url: url,
            statusCode: status,
            responseBytes: responseBytes,
            requestBytes: requestBytes,
            errorDescription: error.map(Self.describe),
            requestHeaders: request.map { redactedHeaderFields($0.allHTTPHeaderFields ?? [:]) },
            requestBody: request.flatMap { capturedRequestBody($0, body: requestBody) },
            responseBody: capturedResponseBody(of: task)
        )
    }

    // MARK: - URLSessionDataDelegate

    /// Buffers the start of a text response while body capture is on. Does
    /// nothing (and allocates nothing) when it's off.
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let encoder = bodyEncoder else { return }
        let key = ObjectIdentifier(dataTask)
        lock.withLock {
            var buffer: ResponseBodyBuffer
            if let existing = responseBuffers[key] {
                buffer = existing
            } else {
                buffer = ResponseBodyBuffer()
                buffer.skipped = !NetworkBodyEncoder.isTextual(Self.contentType(of: dataTask.response), sample: data)
            }
            buffer.totalBytes += data.count
            let room = encoder.bufferLimit - buffer.data.count
            if !buffer.skipped, room > 0 {
                buffer.data.append(data.prefix(room))
            }
            responseBuffers[key] = buffer
        }
    }

    // MARK: - Private

    /// Domain, code and message only. `String(describing:)` on a `URLError`
    /// includes its userInfo, which holds the full, unredacted failing URL.
    static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }

    private func capturedRequestBody(_ request: URLRequest, body: Data?) -> NetworkBody? {
        guard let encoder = bodyEncoder, let body = body ?? request.httpBody else { return nil }
        return encoder.body(
            from: body,
            totalBytes: body.count,
            contentType: request.value(forHTTPHeaderField: "Content-Type")
        )
    }

    func capturedResponseBody(of task: URLSessionTask) -> NetworkBody? {
        guard let encoder = bodyEncoder else { return nil }
        let buffer = lock.withLock { responseBuffers.removeValue(forKey: ObjectIdentifier(task)) }
        guard let buffer, !buffer.skipped else { return nil }
        return encoder.body(
            from: buffer.data,
            totalBytes: buffer.totalBytes,
            contentType: Self.contentType(of: task.response)
        )
    }

    /// The response's `Content-Type` header, or its MIME type for non-HTTP responses.
    static func contentType(of response: URLResponse?) -> String? {
        if let http = response as? HTTPURLResponse {
            return http.value(forHTTPHeaderField: "Content-Type")
        }
        return response?.mimeType
    }

    func redactedHeaderFields(_ headers: [String: String]) -> [String: String] {
        var redacted = headers
        for key in headers.keys where sensitiveHeaders.contains(key.lowercased()) {
            redacted[key] = "[REDACTED]"
        }
        return redacted
    }

    func redactedHeaders(_ headers: [String: String]) -> String {
        headers
            .map { key, value in sensitiveHeaders.contains(key.lowercased()) ? "\(key)=[REDACTED]" : "\(key)=\(value)" }
            .sorted()
            .joined(separator: " ")
    }
}

public extension URLRequest {
    /// Adds a W3C `traceparent` header for the current ``TraceContext`` (a child
    /// span), if one is active and the header isn't already set.
    mutating func addTraceparentHeader() {
        guard value(forHTTPHeaderField: "traceparent") == nil, let trace = CurrentTrace.current else { return }
        setValue(trace.childSpan().traceparent, forHTTPHeaderField: "traceparent")
    }
}
