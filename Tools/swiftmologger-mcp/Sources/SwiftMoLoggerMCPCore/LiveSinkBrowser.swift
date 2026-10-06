#if canImport(Network)
import Foundation
import Network

/// Discovers devices advertising `_swiftmologger._tcp` (LiveSink) on the local network,
/// connects to each one, and reports what happens as an ordered stream of ``DeviceEvent``s.
///
/// Every callback runs on one serial queue and every event goes through a single
/// stream, so lines from a device arrive in the order they were sent.
public final class LiveSinkBrowser: @unchecked Sendable {
    // @unchecked: all mutable state below is only touched on `queue`.
    private let queue = DispatchQueue(label: "swiftmologger.mcp.browser")
    private var browser: NWBrowser?
    private var endpoints: [String: NWEndpoint] = [:]
    private var connections: [String: NWConnection] = [:]
    private var splitters: [String: LineSplitter] = [:]
    private var retryDelays: [String: TimeInterval] = [:]
    private var continuation: AsyncStream<DeviceEvent>.Continuation?

    public static let serviceType = "_swiftmologger._tcp"

    public init() {}

    /// Starts browsing. Call once; the stream ends when ``stop()`` is called.
    public func start() -> AsyncStream<DeviceEvent> {
        let (stream, continuation) = AsyncStream<DeviceEvent>.makeStream(bufferingPolicy: .unbounded)
        queue.async { [self] in
            self.continuation = continuation
            let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
            browser.browseResultsChangedHandler = { [weak self] _, changes in
                self?.handle(changes)
            }
            browser.start(queue: queue)
            self.browser = browser
        }
        return stream
    }

    public func stop() {
        queue.async { [self] in
            browser?.cancel()
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
            continuation?.finish()
        }
    }

    private func handle(_ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case let .added(result):
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                endpoints[name] = result.endpoint
                continuation?.yield(.discovered(device: name))
                connect(name)
            case let .removed(result):
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                endpoints[name] = nil
                connections.removeValue(forKey: name)?.cancel()
                continuation?.yield(.gone(device: name))
            default:
                break
            }
        }
    }

    private func connect(_ name: String) {
        guard let endpoint = endpoints[name], connections[name] == nil else { return }
        let connection = NWConnection(to: endpoint, using: .tcp)
        connections[name] = connection
        splitters[name] = LineSplitter()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.retryDelays[name] = nil
                self.continuation?.yield(.connected(device: name))
                self.receive(on: connection, name: name)
            case .failed, .cancelled:
                self.dropConnection(connection, name: name)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, name: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty, var splitter = self.splitters[name] {
                for line in splitter.append(data) {
                    self.continuation?.yield(.line(device: name, data: line))
                }
                self.splitters[name] = splitter
            }
            if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, name: name)
            }
        }
    }

    /// Forgets the connection and, while Bonjour still lists the device, reconnects
    /// with exponential backoff (0.5 s doubling to 10 s).
    private func dropConnection(_ connection: NWConnection, name: String) {
        guard connections[name] === connection else { return }
        connections[name] = nil
        continuation?.yield(.disconnected(device: name))
        guard endpoints[name] != nil else { return }
        let delay = retryDelays[name].map { min($0 * 2, 10) } ?? 0.5
        retryDelays[name] = delay
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect(name)
        }
    }
}
#endif
