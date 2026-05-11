import Foundation
import Network
import SwiftMoLogger

/// On-device server that advertises itself via Bonjour
/// (`_swiftmologger._tcp`) and streams every `LogEntry` as JSON-Lines to
/// any connected client. Pair with the `swiftmologger-inspector` CLI on
/// Mac to get a zero-config live tail.
///
/// **Use in dev/QA builds only.** It opens a local network port and emits
/// every log line in the clear.
///
/// ```swift
/// #if DEBUG
/// let sink = LiveSink()
/// try sink.start()
/// SwiftMoLogger.addEngine(sink)
/// #endif
/// ```
public final class LiveSink: LogEngine, @unchecked Sendable {
    public static let serviceType = "_swiftmologger._tcp"

    public let engineID: String = "swiftmologger.diagnostics.livesink"
    public let minimumLevel: LogLevel

    public let port: NWEndpoint.Port
    public let serviceName: String

    private let queue = DispatchQueue(label: "swiftmologger.livesink", qos: .utility)
    private let encoder: JSONEncoder
    private var listener: NWListener?
    private var lock = os_unfair_lock_s()
    private var clients: [NWConnection] = []

    public init(
        port: NWEndpoint.Port = .any,
        serviceName: String? = nil,
        minimumLevel: LogLevel = .trace
    ) {
        self.port = port
        self.minimumLevel = minimumLevel
        self.serviceName = serviceName ?? Bundle.main.bundleIdentifier ?? "SwiftMoLogger"
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    public func start() throws {
        guard listener == nil else { return }
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: port)
        listener.service = NWListener.Service(name: serviceName, type: LiveSink.serviceType)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: SwiftMoLogger.notice("LiveSink ready", tag: .Development.debug)
            case .failed(let error): SwiftMoLogger.error("LiveSink failed: \(error)", tag: .Development.debug)
            default: break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.listener?.cancel()
            self.listener = nil
            os_unfair_lock_lock(&self.lock)
            for client in self.clients { client.cancel() }
            self.clients.removeAll()
            os_unfair_lock_unlock(&self.lock)
        }
    }

    public func log(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self,
                  let data = try? self.encoder.encode(entry) else { return }
            var line = data
            line.append(0x0A)
            os_unfair_lock_lock(&self.lock)
            let snapshot = self.clients
            os_unfair_lock_unlock(&self.lock)
            for client in snapshot {
                client.send(content: line, completion: .contentProcessed { _ in })
            }
        }
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self = self, let connection = connection else { return }
            switch state {
            case .ready:
                os_unfair_lock_lock(&self.lock)
                self.clients.append(connection)
                os_unfair_lock_unlock(&self.lock)
                self.sendBanner(to: connection)
            case .failed, .cancelled:
                os_unfair_lock_lock(&self.lock)
                self.clients.removeAll { $0 === connection }
                os_unfair_lock_unlock(&self.lock)
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func sendBanner(to connection: NWConnection) {
        let banner: [String: Any] = [
            "service": "SwiftMoLogger.LiveSink",
            "version": 1,
            "app": serviceName,
            "started_at": ISO8601DateFormatter().string(from: Date())
        ]
        if let data = try? JSONSerialization.data(withJSONObject: banner) {
            var line = data
            line.append(0x0A)
            connection.send(content: line, completion: .contentProcessed { _ in })
        }
    }
}
