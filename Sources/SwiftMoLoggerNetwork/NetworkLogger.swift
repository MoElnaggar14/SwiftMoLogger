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
/// For each task it logs the request (with sensitive headers redacted) and the
/// outcome (status, bytes, duration), leaves breadcrumbs, and records a
/// ``NetworkEvent`` for the Diagnostics Hub's waterfall. It only observes: it
/// never changes requests, buffers bodies or affects redirects.
///
/// To connect requests to a backend trace, call `request.addTraceparentHeader()`
/// inside `TraceContext.run { … }`.
public final class NetworkLogger: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// Header names (lower-case) whose values are never logged.
    public static let defaultSensitiveHeaders: Set<String> = [
        "authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token", "proxy-authorization"
    ]

    private let logger: MoLogger
    private let events: NetworkEventStore?
    private let breadcrumbs: BreadcrumbStore?
    private let sensitiveHeaders: Set<String>

    /// Tasks whose request was already logged by `didCreateTask`. That callback
    /// only reaches session-level delegates, so tasks using a per-task delegate
    /// (`session.data(for:delegate:)`) get their request logged with the outcome.
    private let lock = UnfairLock()
    private var announcedTasks: Set<ObjectIdentifier> = []

    /// - Parameters:
    ///   - logger: Receives request and response entries. Untagged entries get `.api`.
    ///   - events: Records each task for the Diagnostics Hub. `nil` to skip.
    ///   - breadcrumbs: Gets a breadcrumb per request and response. `nil` to skip.
    ///   - sensitiveHeaders: Header names (any case) whose values are redacted.
    public init(
        logger: MoLogger,
        events: NetworkEventStore? = nil,
        breadcrumbs: BreadcrumbStore? = nil,
        sensitiveHeaders: Set<String> = NetworkLogger.defaultSensitiveHeaders
    ) {
        self.logger = logger.tag == nil ? logger.with(tag: .api) : logger
        self.events = events
        self.breadcrumbs = breadcrumbs
        self.sensitiveHeaders = Set(sensitiveHeaders.map { $0.lowercased() })
    }

    /// Logs through the environment's logger and records into its stores.
    public convenience init(environment: LogEnvironment) {
        self.init(logger: environment.logger, events: environment.networkEvents, breadcrumbs: environment.breadcrumbs)
    }

    // MARK: - URLSessionTaskDelegate

    public func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        lock.withLock { _ = announcedTasks.insert(ObjectIdentifier(task)) }
        logRequest(of: task)
    }

    private func logRequest(of task: URLSessionTask) {
        guard let request = task.originalRequest ?? task.currentRequest else { return }
        logger.info("HTTP request", metadata: [
            "http.method": .string(request.httpMethod ?? "GET"),
            "http.url": .string(request.url?.absoluteString ?? "?"),
            "http.headers": .string(redactedHeaders(request.allHTTPHeaderFields ?? [:])),
            "http.body_bytes": .int(Int64(request.httpBody?.count ?? 0))
        ])
        breadcrumbs?.record("→ \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "?")", category: .network)
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
        let announced = lock.withLock { announcedTasks.remove(ObjectIdentifier(task)) != nil }
        if !announced { logRequest(of: task) }

        let error = task.error
        let request = task.originalRequest
        let url = task.response?.url ?? request?.url ?? URL(fileURLWithPath: "/")
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
                "error": .string(String(describing: error))
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

        events?.record(NetworkEvent(
            startedAt: interval.start,
            endedAt: interval.end,
            method: method,
            url: url,
            statusCode: status,
            responseBytes: responseBytes,
            requestBytes: requestBytes,
            errorDescription: error.map { String(describing: $0) }
        ))
    }

    // MARK: - Private

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
