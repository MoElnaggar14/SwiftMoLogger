import Foundation
import SwiftMoLogger

/// Base class for engines that ship batched ``LogEntry`` values to an HTTP
/// endpoint.
///
/// Owns the batching, debouncing, retry-with-backoff, and graceful shutdown
/// behaviour. Subclasses (or callers using ``init(endpoint:transform:)``)
/// only need to describe how to map a batch of entries into a request body.
///
/// Designed for telemetry pipelines where dropping logs is preferable to
/// blocking the caller — `log(_:)` is O(1) and the network work happens on
/// a private utility queue.
public class HTTPLogShipper: LogEngine, @unchecked Sendable {
    public struct Configuration: Sendable {
        public let endpoint: URL
        public let headers: [String: String]
        public let method: String
        public let batchSize: Int
        public let flushInterval: TimeInterval
        public let maxRetries: Int
        public let maxBufferedEntries: Int

        public init(
            endpoint: URL,
            headers: [String: String] = [:],
            method: String = "POST",
            batchSize: Int = 50,
            flushInterval: TimeInterval = 5,
            maxRetries: Int = 3,
            maxBufferedEntries: Int = 5_000
        ) {
            self.endpoint = endpoint
            self.headers = headers
            self.method = method
            self.batchSize = batchSize
            self.flushInterval = flushInterval
            self.maxRetries = maxRetries
            self.maxBufferedEntries = maxBufferedEntries
        }
    }

    public let engineID: String
    public let minimumLevel: LogLevel
    public let configuration: Configuration

    /// Synchronously called on the shipper's queue. Return a request body
    /// (typically JSON) for the given batch.
    public typealias BodyBuilder = @Sendable (_ entries: [LogEntry]) throws -> Data

    private let session: URLSession
    private let queue: DispatchQueue
    private let buildBody: BodyBuilder
    private var pending: [LogEntry] = []
    private var flushScheduled = false

    public init(
        engineID: String = "swiftmologger.remote.http",
        minimumLevel: LogLevel = .info,
        configuration: Configuration,
        session: URLSession = .shared,
        body: @escaping BodyBuilder = HTTPLogShipper.defaultJSONBody
    ) {
        self.engineID = engineID
        self.minimumLevel = minimumLevel
        self.configuration = configuration
        self.session = session
        self.queue = DispatchQueue(label: "\(engineID).shipper", qos: .utility)
        self.buildBody = body
    }

    public func log(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pending.append(entry)
            if self.pending.count > self.configuration.maxBufferedEntries {
                self.pending.removeFirst(self.pending.count - self.configuration.maxBufferedEntries)
            }
            if self.pending.count >= self.configuration.batchSize {
                self.flushLocked()
            } else if !self.flushScheduled {
                self.flushScheduled = true
                self.queue.asyncAfter(deadline: .now() + self.configuration.flushInterval) { [weak self] in
                    guard let self = self else { return }
                    self.flushScheduled = false
                    self.flushLocked()
                }
            }
        }
    }

    /// Force an immediate flush. Returns once the in-flight request has
    /// been issued (not awaited). Useful from `applicationWillTerminate`.
    public func flush() {
        queue.sync { self.flushLocked() }
    }

    // MARK: - Private

    private func flushLocked() {
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        send(batch, attempt: 0)
    }

    private func send(_ batch: [LogEntry], attempt: Int) {
        let body: Data
        do {
            body = try buildBody(batch)
        } catch {
            // Body construction failed — drop batch, log to system only.
            NSLog("HTTPLogShipper body build failed: %@", String(describing: error))
            return
        }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = configuration.method
        request.httpBody = body
        for (key, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let task = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }
            let http = response as? HTTPURLResponse
            let success = error == nil && (200..<300).contains(http?.statusCode ?? 0)
            if success { return }
            guard attempt < self.configuration.maxRetries else {
                NSLog("HTTPLogShipper dropped batch after %d retries", attempt)
                return
            }
            let delay = pow(2.0, Double(attempt))
            self.queue.asyncAfter(deadline: .now() + delay) {
                self.send(batch, attempt: attempt + 1)
            }
        }
        task.resume()
    }

    /// Default JSON envelope: `{"entries": [LogEntry, …]}`.
    public static let defaultJSONBody: BodyBuilder = { entries in
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(["entries": entries])
    }
}
