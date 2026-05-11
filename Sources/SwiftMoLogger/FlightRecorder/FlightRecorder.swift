import Foundation

/// "Black box" recorder for crash forensics.
///
/// Periodically snapshots the last `window` worth of `LogEntry`s, breadcrumbs,
/// network events, signpost spans, and vitals ticks to a small file inside
/// the user's caches directory. On next launch, ``recoverLastSession()``
/// returns the snapshot if the previous run never had a clean shutdown —
/// answering "what was happening in the seconds before the app died?".
///
/// Cost is bounded: the recorder writes at most every `flushInterval`
/// seconds, encoding the current ring-buffer contents in a single
/// `JSONEncoder` pass on a background queue.
///
/// ```swift
/// let recorder = FlightRecorder()
/// recorder.start()
///
/// // ...later, e.g. in didFinishLaunching:
/// if let session = FlightRecorder.recoverLastSession() {
///     SwiftMoLogger.warn("Recovered \(session.entries.count) entries from a crashed session")
///     // Optionally feed back into the Diagnostics Hub or upload to a backend.
/// }
/// ```
public final class FlightRecorder: @unchecked Sendable {
    public struct Session: Sendable, Codable {
        public let recordedAt: Date
        public let appVersion: String
        public let osVersion: String
        public let entries: [LogEntry]
        public let breadcrumbs: [Breadcrumb]
        public let networkEvents: [NetworkEvent]
        public let signpostEvents: [SignpostEvent]
        public let vitals: [VitalsTick]
    }

    public let fileURL: URL
    public let window: TimeInterval
    public let flushInterval: TimeInterval

    private let memory: MemoryLogEngine
    private let queue: DispatchQueue
    private var timer: DispatchSourceTimer?
    private var stopped = false

    public init(
        fileURL: URL? = nil,
        window: TimeInterval = 120,
        flushInterval: TimeInterval = 2,
        capacity: Int = 1_000
    ) {
        self.fileURL = fileURL ?? FlightRecorder.defaultFileURL
        self.window = window
        self.flushInterval = flushInterval
        self.memory = MemoryLogEngine(capacity: capacity)
        self.queue = DispatchQueue(label: "swiftmologger.flightrecorder", qos: .utility)
    }

    /// Begin recording. Also registers the recorder as a log engine so it
    /// captures everything passing through the registry.
    public func start() {
        guard timer == nil else { return }
        if !SwiftMoLogger.allEngines().contains(where: { $0.engineID == memory.engineID }) {
            SwiftMoLogger.addEngine(memory)
        }
        markSessionAlive(true)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        timer.setEventHandler { [weak self] in self?.flushSync() }
        timer.resume()
        self.timer = timer
    }

    /// Stop and mark the session as cleanly terminated. Any subsequent
    /// `recoverLastSession()` call returns `nil` since there was no crash.
    public func stop() {
        queue.sync {
            guard !stopped else { return }
            stopped = true
            timer?.cancel()
            timer = nil
            self.markSessionAlive(false)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Flush the current ring buffer to disk immediately.
    public func flush() {
        queue.sync { flushSync() }
    }

    // MARK: - Recovery

    /// If the previous session was not stopped cleanly, return the last
    /// recorded snapshot. Returns `nil` after a clean shutdown.
    public static func recoverLastSession(from fileURL: URL = FlightRecorder.defaultFileURL) -> Session? {
        guard wasAlive(in: UserDefaults.standard) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Session.self, from: data)
    }

    // MARK: - Private

    static let defaultFileURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwiftMoLogger", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("flight-recorder.json")
    }()

    private static let aliveKey = "SwiftMoLogger.FlightRecorder.alive"

    private static func wasAlive(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: aliveKey)
    }

    private func markSessionAlive(_ alive: Bool) {
        UserDefaults.standard.set(alive, forKey: FlightRecorder.aliveKey)
    }

    private func flushSync() {
        let cutoff = Date().addingTimeInterval(-window)
        let allEntries = memory.snapshot()
        let entries = allEntries.filter { $0.timestamp >= cutoff }
        let session = Session(
            recordedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            entries: entries,
            breadcrumbs: SwiftMoLogger.breadcrumbs(),
            networkEvents: NetworkEventStore.shared.snapshot().filter { $0.startedAt >= cutoff },
            signpostEvents: SignpostEventStore.shared.snapshot().filter { $0.startedAt >= cutoff },
            vitals: VitalsHistoryStore.shared.snapshot().filter { $0.timestamp >= cutoff }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(session)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("FlightRecorder flush failed: %@", String(describing: error))
        }
    }
}
