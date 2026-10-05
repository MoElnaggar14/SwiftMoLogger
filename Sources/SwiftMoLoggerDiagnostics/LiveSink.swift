import Foundation
import Network
import SwiftMoLogger

/// On-device server that advertises itself via Bonjour
/// (`_swiftmologger._tcp`) and streams every `LogEntry` as JSON-Lines to
/// any connected client. Pair with the `swiftmologger-inspector` CLI on
/// Mac to get a zero-config live tail.
///
/// **Use in dev/QA builds only.** It opens a local network port and emits
/// every log line in the clear, so ``start()`` does nothing in release builds
/// unless you pass `allowInRelease: true` (for example for an internal QA build).
///
/// On iOS the app's Info.plist needs `NSLocalNetworkUsageDescription` and
/// `NSBonjourServices` containing `_swiftmologger._tcp`.
///
/// ```swift
/// #if DEBUG
/// let sink = LiveSink(statusLogger: logging.logger)
/// try sink.start()
/// logging.registry.addEngine(sink)
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
    private let lock = UnfairLock()
    private var clients: [NWConnection] = []
    private let statusLogger: MoLogger?
    private let allowInRelease: Bool

    /// - Parameters:
    ///   - statusLogger: Receives "ready" / "failed" notices about the listener.
    ///   - allowInRelease: Lets ``start()`` open the listener in non-DEBUG builds.
    public init(
        port: NWEndpoint.Port = .any,
        serviceName: String? = nil,
        minimumLevel: LogLevel = .trace,
        statusLogger: MoLogger? = nil,
        allowInRelease: Bool = false
    ) {
        self.statusLogger = statusLogger
        self.allowInRelease = allowInRelease
        self.port = port
        self.minimumLevel = minimumLevel
        self.serviceName = serviceName ?? Bundle.main.bundleIdentifier ?? "SwiftMoLogger"
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
    }

    public func start() throws {
        guard listener == nil else { return }
        #if !DEBUG
        guard allowInRelease else {
            statusLogger?.warning(
                "LiveSink not started in a release build. Pass allowInRelease: true for internal QA builds.",
                tag: .Development.debug
            )
            return
        }
        #endif
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: port)
        listener.service = NWListener.Service(name: serviceName, type: LiveSink.serviceType)
        listener.stateUpdateHandler = { [statusLogger] state in
            switch state {
            case .ready: statusLogger?.notice("LiveSink ready", tag: .Development.debug)
            case .failed(let error): statusLogger?.error("LiveSink failed: \(error)", tag: .Development.debug)
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
            self.lock.lock()
            for client in self.clients { client.cancel() }
            self.clients.removeAll()
            self.lock.unlock()
        }
    }

    public func log(_ entry: LogEntry) {
        queue.async { [weak self] in
            guard let self = self,
                  let data = try? self.encoder.encode(entry) else { return }
            var line = data
            line.append(0x0A)
            self.lock.lock()
            let snapshot = self.clients
            self.lock.unlock()
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
                self.lock.lock()
                self.clients.append(connection)
                self.lock.unlock()
                self.sendBanner(to: connection)
            case .failed, .cancelled:
                self.lock.lock()
                self.clients.removeAll { $0 === connection }
                self.lock.unlock()
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
