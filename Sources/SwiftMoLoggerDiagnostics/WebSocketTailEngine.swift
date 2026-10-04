import Foundation
import SwiftMoLogger

/// Streams log entries as line-delimited JSON over a WebSocket connection
/// to a developer dashboard or CLI tail receiver.
///
/// Designed for development / on-device QA — buffer is small, no retry
/// avalanche, and the engine silently no-ops if the connection drops. Pair
/// with a reverse-proxy like `wscat` for ad-hoc tailing:
///
/// ```bash
/// wscat -l 9001
/// # in the app:
/// SwiftMoLogger.addEngine(WebSocketTailEngine(url: URL(string: "ws://192.168.1.42:9001")!))
/// ```
public final class WebSocketTailEngine: NSObject, LogEngine, @unchecked Sendable, URLSessionWebSocketDelegate {
    public let engineID: String = "swiftmologger.diagnostics.wstail"
    public let minimumLevel: LogLevel

    private let url: URL
    private let queue = DispatchQueue(label: "swiftmologger.wstail", qos: .utility)
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private let encoder: JSONEncoder
    private let lock = UnfairLock()
    private var connected = false

    public init(url: URL, minimumLevel: LogLevel = .trace) {
        precondition(url.scheme == "ws" || url.scheme == "wss")
        self.url = url
        self.minimumLevel = minimumLevel
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        super.init()
        connect()
    }

    public func log(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self,
                  let task = self.task,
                  self.isConnected,
                  let data = try? self.encoder.encode(entry),
                  let string = String(data: data, encoding: .utf8) else { return }
            task.send(.string(string)) { _ in /* silent drop on error */ }
        }
    }

    /// Close the socket and release the session. `URLSession` retains its
    /// delegate (this engine) until invalidated, so call this when you're done
    /// or the engine is never deallocated.
    public func disconnect() {
        queue.async { [weak self] in
            guard let self else { return }
            self.task?.cancel(with: .goingAway, reason: nil)
            self.task = nil
            self.session?.invalidateAndCancel()
            self.session = nil
            self.setConnected(false)
        }
    }

    private var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    private func setConnected(_ value: Bool) {
        lock.lock()
        connected = value
        lock.unlock()
    }

    private func connect() {
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
    }

    // MARK: - URLSessionWebSocketDelegate

    public func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        setConnected(true)
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        setConnected(false)
    }
}
