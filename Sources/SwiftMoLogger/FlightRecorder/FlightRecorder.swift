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
/// seconds, and only when something new was recorded, encoding the current
/// ring-buffer contents in a single `JSONEncoder` pass on a background queue.
///
/// On iOS, tvOS and visionOS it also flushes and marks the session clean when
/// the app moves to the background, and marks it running again on return. An
/// app the user swipes away (or the system evicts) while suspended therefore
/// isn't reported as a crash; a crash while running in the background isn't
/// either.
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
    /// What's registered with the registry: `memory`, possibly behind a redactor.
    private let recordingEngine: any LogEngine
    private let redactor: Redactor?
    private let aliveKey: String
    private let queue: DispatchQueue
    // `timer`, `recovered`, `lastFlushed` and `lifecycleObservers` are only touched on `queue`.
    private var timer: DispatchSourceTimer?
    private var recovered: Session?
    private var lastFlushed: Fingerprint?
    private var lifecycleObservers: [any NSObjectProtocol] = []

    /// The newest item of each source at the last write. An unchanged snapshot
    /// isn't rewritten.
    private struct Fingerprint: Equatable {
        var entry: UUID?
        var breadcrumb: UUID?
        var networkEvent: UUID?
        var signpostEvent: UUID?
        var vitals: UUID?
    }

    /// - Parameters:
    ///   - environment: The registry to record from and the stores to snapshot.
    ///   - defaults: Where the "session is running" flag lives.
    ///   - redactor: Redacts everything before it's written (entries, breadcrumbs,
    ///     and network events, whose URLs also lose their query string), so the
    ///     file on disk never holds raw secrets or PII. `nil` keeps data as captured.
    public init(
        environment: LogEnvironment,
        fileURL: URL? = nil,
        window: TimeInterval = 120,
        flushInterval: TimeInterval = 5,
        capacity: Int = 1_000,
        defaults: UserDefaults = .standard,
        redactor: Redactor? = nil
    ) {
        self.environment = environment
        self.defaults = defaults
        self.fileURL = fileURL ?? FlightRecorder.defaultFileURL
        self.window = window
        self.flushInterval = flushInterval
        let memory = MemoryLogEngine(capacity: capacity)
        self.memory = memory
        self.recordingEngine = redactor.map { RedactingLogEngine(wrapping: memory, redactor: $0) } ?? memory
        self.redactor = redactor
        self.aliveKey = FlightRecorder.aliveKey(for: self.fileURL)
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
            environment.registry.addEngine(recordingEngine)
            markSessionAlive(true)
            lastFlushed = nil
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(
                deadline: .now() + flushInterval,
                repeating: flushInterval,
                leeway: .milliseconds(Int(flushInterval * 100))
            )
            timer.setEventHandler { [weak self] in self?.flushSync(force: false) }
            timer.resume()
            self.timer = timer
            observeLifecycle()
        }
    }

    /// Stop and mark the session as cleanly terminated, so the next launch
    /// doesn't report a crash.
    public func stop() {
        queue.sync {
            guard let timer else { return }
            timer.cancel()
            self.timer = nil
            stopObservingLifecycle()
            environment.registry.removeEngine(id: recordingEngine.engineID)
            markSessionAlive(false)
            lastFlushed = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Flush the current ring buffer to disk immediately.
    public func flush() {
        queue.sync { _ = flushSync(force: true) }
    }

    /// What the timer does: writes only if something was recorded since the
    /// last write. Returns whether it wrote.
    @discardableResult
    func flushIfChanged() -> Bool {
        queue.sync { flushSync(force: false) }
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
        guard defaults.bool(forKey: aliveKey(for: fileURL)) else { return nil }
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

    /// One flag per file, so independent recorders (two environments, an app
    /// and a framework) can't mark each other's sessions as clean.
    static func aliveKey(for fileURL: URL) -> String {
        "SwiftMoLogger.FlightRecorder.alive.\(fileURL.standardizedFileURL.path)"
    }

    private func markSessionAlive(_ alive: Bool) {
        defaults.set(alive, forKey: aliveKey)
    }

    deinit {
        // A recorder released without stop() shouldn't leave its engine behind.
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        environment.registry.removeEngine(id: recordingEngine.engineID)
    }

    // MARK: - App lifecycle

    // The UIApplication notification names, spelled out: UIKit's constants are
    // main-actor isolated and this runs on `queue`. The values are stable API.
    private static let didEnterBackground = Notification.Name("UIApplicationDidEnterBackgroundNotification")
    private static let willEnterForeground = Notification.Name("UIApplicationWillEnterForegroundNotification")

    // Called on `queue`.
    private func observeLifecycle() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let background = center.addObserver(
            forName: Self.didEnterBackground, object: nil, queue: nil
        ) { [weak self] _ in self?.appDidEnterBackground() }
        let foreground = center.addObserver(
            forName: Self.willEnterForeground, object: nil, queue: nil
        ) { [weak self] _ in self?.appWillEnterForeground() }
        lifecycleObservers = [background, foreground]
        #endif
    }

    // Called on `queue`.
    private func stopObservingLifecycle() {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        lifecycleObservers.removeAll()
    }

    /// Suspended apps can be terminated without warning, which isn't a crash:
    /// write the latest snapshot and mark the session clean.
    private func appDidEnterBackground() {
        queue.sync {
            guard timer != nil else { return }
            _ = flushSync(force: true)
            markSessionAlive(false)
        }
    }

    private func appWillEnterForeground() {
        queue.sync {
            guard timer != nil else { return }
            markSessionAlive(true)
        }
    }

    private func redacted(_ crumb: Breadcrumb) -> Breadcrumb {
        guard let redactor else { return crumb }
        return Breadcrumb(
            id: crumb.id,
            timestamp: crumb.timestamp,
            category: crumb.category,
            message: redactor.redact(crumb.message).output,
            metadata: redactor.redact(crumb.metadata)
        )
    }

    private func redacted(_ event: NetworkEvent) -> NetworkEvent {
        guard let redactor else { return event }
        return NetworkEvent(
            id: event.id,
            startedAt: event.startedAt,
            endedAt: event.endedAt,
            method: event.method,
            url: Self.strippingQuery(event.url),
            statusCode: event.statusCode,
            responseBytes: event.responseBytes,
            requestBytes: event.requestBytes,
            errorDescription: event.errorDescription.map { redactor.redact($0).output }
        )
    }

    /// Query strings routinely carry tokens; keep scheme, host and path only.
    private static func strippingQuery(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    @discardableResult
    private func flushSync(force: Bool) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let allEntries = memory.snapshot()
        let breadcrumbs = environment.breadcrumbs.snapshot()
        let networkEvents = environment.networkEvents.snapshot()
        let signpostEvents = environment.signposts.snapshot()
        let vitals = environment.vitals.snapshot()
        let fingerprint = Fingerprint(
            entry: allEntries.last?.id,
            breadcrumb: breadcrumbs.last?.id,
            networkEvent: networkEvents.last?.id,
            signpostEvent: signpostEvents.last?.id,
            vitals: vitals.last?.id
        )
        // Nothing new since the last write: skip the encode and the disk write.
        guard force || fingerprint != lastFlushed else { return false }
        let session = Session(
            recordedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            entries: allEntries.filter { $0.timestamp >= cutoff },
            breadcrumbs: breadcrumbs.map(redacted),
            networkEvents: networkEvents.filter { $0.startedAt >= cutoff }.map(redacted),
            signpostEvents: signpostEvents.filter { $0.startedAt >= cutoff },
            vitals: vitals.filter { $0.timestamp >= cutoff }
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
            lastFlushed = fingerprint
            return true
        } catch {
            NSLog("FlightRecorder flush failed: %@", String(describing: error))
            return false
        }
    }
}
