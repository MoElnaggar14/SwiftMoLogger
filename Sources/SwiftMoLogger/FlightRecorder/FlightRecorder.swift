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
/// // In didFinishLaunching:
/// let recorder = FlightRecorder(environment: logging)
/// recorder.start()
/// if let session = recorder.crashedSession {
///     logging.logger.warning("Recovered \(session.entries.count) entries from a crashed session")
///     // Optionally feed back into the Diagnostics Hub or upload to a backend.
/// }
/// ```
///
/// `start()` captures the previous session before marking the new one as
/// running, so ``crashedSession`` is safe to read at any point afterwards.
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

    private let environment: LogEnvironment
    private let defaults: UserDefaults
    private let memory: MemoryLogEngine
    private let queue: DispatchQueue
    // `timer` and `recovered` are only touched on `queue`.
    private var timer: DispatchSourceTimer?
    private var recovered: Session?

    /// - Parameters:
    ///   - environment: The registry to record from and the stores to snapshot.
    ///   - defaults: Where the "session is running" flag lives.
    public init(
        environment: LogEnvironment,
        fileURL: URL? = nil,
        window: TimeInterval = 120,
        flushInterval: TimeInterval = 2,
        capacity: Int = 1_000,
        defaults: UserDefaults = .standard
    ) {
        self.environment = environment
        self.defaults = defaults
        self.fileURL = fileURL ?? FlightRecorder.defaultFileURL
        self.window = window
        self.flushInterval = flushInterval
        self.memory = MemoryLogEngine(capacity: capacity)
        self.queue = DispatchQueue(label: "swiftmologger.flightrecorder", qos: .utility)
    }

    /// The snapshot left by the previous run if it didn't stop cleanly,
    /// captured by the first ``start()``. `nil` after a clean shutdown.
    public var crashedSession: Session? {
        queue.sync { recovered }
    }

    /// Begin recording. Also registers the recorder as a log engine so it
    /// captures everything passing through the registry. Calling it again
    /// after ``stop()`` resumes recording.
    public func start() {
        queue.sync {
            guard timer == nil else { return }
            if recovered == nil {
                recovered = FlightRecorder.recoverLastSession(from: fileURL, defaults: defaults)
            }
            // Always register *this* recorder's private memory engine; it has
            // a unique id so it can't replace (or be replaced by) another
            // MemoryLogEngine in the registry.
            environment.registry.addEngine(memory)
            markSessionAlive(true)
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
            timer.setEventHandler { [weak self] in self?.flushSync() }
            timer.resume()
            self.timer = timer
        }
    }

    /// Stop and mark the session as cleanly terminated, so the next launch
    /// doesn't report a crash.
    public func stop() {
        queue.sync {
            guard let timer else { return }
            timer.cancel()
            self.timer = nil
            environment.registry.removeEngine(id: memory.engineID)
            markSessionAlive(false)
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
    ///
    /// Call this *before* any recorder's ``start()`` in the new process (which
    /// marks the new session as running), or read ``crashedSession`` instead.
    public static func recoverLastSession(
        from fileURL: URL = FlightRecorder.defaultFileURL,
        defaults: UserDefaults = .standard
    ) -> Session? {
        guard wasAlive(in: defaults) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return try? decoder.decode(Session.self, from: data)
    }

    // MARK: - Private

    public static let defaultFileURL: URL = {
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
        defaults.set(alive, forKey: FlightRecorder.aliveKey)
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
            breadcrumbs: environment.breadcrumbs.snapshot(),
            networkEvents: environment.networkEvents.snapshot().filter { $0.startedAt >= cutoff },
            signpostEvents: environment.signposts.snapshot().filter { $0.startedAt >= cutoff },
            vitals: environment.vitals.snapshot().filter { $0.timestamp >= cutoff }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        do {
            let data = try encoder.encode(session)
            // A custom `fileURL` may point into a folder that doesn't exist yet.
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("FlightRecorder flush failed: %@", String(describing: error))
        }
    }
}
