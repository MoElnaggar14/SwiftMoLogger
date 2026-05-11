import Foundation
import Network

/// `swiftmologger-inspector` — discovers iOS / macOS devices running a
/// ``LiveSink`` on the same network via Bonjour, then pretty-prints every
/// log entry they emit.
///
/// Build + run:
///
/// ```
/// swift run swiftmologger-inspector
/// ```
///
/// On the device, in DEBUG:
///
/// ```swift
/// let sink = LiveSink()
/// try sink.start()
/// SwiftMoLogger.addEngine(sink)
/// ```

@main
enum Inspector {
    static func main() {
        let runtime = InspectorRuntime()
        runtime.start()
        RunLoop.main.run()
    }
}

final class InspectorRuntime: @unchecked Sendable {
    private let serviceType = "_swiftmologger._tcp"
    private let queue = DispatchQueue(label: "inspector")
    private var browser: NWBrowser?
    private var connections: [String: NWConnection] = [:]
    private var buffers: [String: Data] = [:]

    func start() {
        print(Ansi.bold("SwiftMoLogger Inspector") + " — discovering \(serviceType) on local network…")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handle(results: results)
        }
        browser.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("browse failed: \(error)")
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    private func handle(results: Set<NWBrowser.Result>) {
        var seen: Set<String> = []
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                seen.insert(name)
                if connections[name] == nil {
                    print(Ansi.green("◉ discovered ") + Ansi.bold(name))
                    connect(to: result.endpoint, name: name)
                }
            }
        }
        for (name, connection) in connections where !seen.contains(name) {
            connection.cancel()
            connections.removeValue(forKey: name)
            buffers.removeValue(forKey: name)
            print(Ansi.dim("◌ gone ") + name)
        }
    }

    private func connect(to endpoint: NWEndpoint, name: String) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connections[name] = connection
        buffers[name] = Data()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                print(Ansi.green("● connected ") + Ansi.bold(name))
                self.receive(on: connection, name: name)
            case .failed(let error):
                print(Ansi.red("✗ \(name): \(error)"))
            default: break
            }
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, name: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let data = data {
                self.buffers[name, default: Data()].append(data)
                self.flushLines(name: name)
            }
            if error == nil && !isComplete {
                self.receive(on: connection, name: name)
            }
        }
    }

    private func flushLines(name: String) {
        guard var buffer = buffers[name] else { return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: line, source: name)
        }
        buffers[name] = buffer
    }

    private func handle(line: Data, source: String) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return
        }
        if object["service"] as? String == "SwiftMoLogger.LiveSink" {
            print(Ansi.dim("…banner from \(source): \(object["app"] ?? "?")"))
            return
        }
        // LogEntry shape
        let level = Self.levelString(from: object["level"])
        let message = object["message"] as? String ?? ""
        let tag = (object["tag"] as? [String: Any])?["rawValue"] as? String ?? ""
        let thread = object["threadName"] as? String ?? ""
        let timestamp = object["timestamp"] as? String ?? ""
        print("\(Ansi.dim(timestamp)) \(level) \(Ansi.cyan(source)) \(Ansi.magenta(tag)) \(Ansi.dim("[" + thread + "]")) \(message)")
    }

    private static func levelString(from raw: Any?) -> String {
        let intValue = raw as? Int ?? -1
        switch intValue {
        case 0: return Ansi.dim("TRACE")
        case 1: return Ansi.dim("DEBUG")
        case 2: return Ansi.blue("INFO ")
        case 3: return Ansi.cyan("NOTE ")
        case 4: return Ansi.yellow("WARN ")
        case 5: return Ansi.red("ERROR")
        case 6: return Ansi.red("CRIT ")
        case 7: return Ansi.red("FAULT")
        default: return "?"
        }
    }
}

enum Ansi {
    static func bold(_ s: String) -> String { "\u{1B}[1m\(s)\u{1B}[0m" }
    static func dim(_ s: String) -> String { "\u{1B}[2m\(s)\u{1B}[0m" }
    static func red(_ s: String) -> String { "\u{1B}[31m\(s)\u{1B}[0m" }
    static func green(_ s: String) -> String { "\u{1B}[32m\(s)\u{1B}[0m" }
    static func yellow(_ s: String) -> String { "\u{1B}[33m\(s)\u{1B}[0m" }
    static func blue(_ s: String) -> String { "\u{1B}[34m\(s)\u{1B}[0m" }
    static func magenta(_ s: String) -> String { "\u{1B}[35m\(s)\u{1B}[0m" }
    static func cyan(_ s: String) -> String { "\u{1B}[36m\(s)\u{1B}[0m" }
}
