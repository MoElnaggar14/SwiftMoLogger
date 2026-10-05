import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

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
/// let recorder = FlightRecorder()
/// recorder.start()
/// if let session = recorder.crashedSession {
///     SwiftMoLogger.warn("Recovered \(session.entries.count) entries from a crashed session")
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

    private let memory: MemoryLogEngine
    private let queue: DispatchQueue
    // `timer`, `recovered` and `lastFlushed` are only touched on `queue`.
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

    public init(
        fileURL: URL? = nil,
        window: TimeInterval = 120,
        flushInterval: TimeInterval = 5,
        capacity: Int = 1_000
    ) {
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
                recovered = FlightRecorder.recoverLastSession(from: fileURL)
            }
            // Always register *this* recorder's private memory engine; it has
            // a unique id so it can't replace (or be replaced by) another
            // MemoryLogEngine in the registry.
            SwiftMoLogger.addEngine(memory)
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
            SwiftMoLogger.removeEngine(id: memory.engineID)
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
    public static func recoverLastSession(from fileURL: URL = FlightRecorder.defaultFileURL) -> Session? {
        guard UserDefaults.standard.bool(forKey: aliveKey(for: fileURL)) else { return nil }
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

    /// One flag per file, so independent recorders can't mark each other's
    /// sessions as clean.
    static func aliveKey(for fileURL: URL) -> String {
        "SwiftMoLogger.FlightRecorder.alive.\(fileURL.standardizedFileURL.path)"
    }

    deinit {
        // A recorder released without stop() shouldn't leave its engine behind.
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
        SwiftMoLogger.removeEngine(id: memory.engineID)
    }

    // Called on `queue`.
    private func observeLifecycle() {
        #if canImport(UIKit) && !os(watchOS)
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let background = center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.appDidEnterBackground() }
        let foreground = center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
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

    private func markSessionAlive(_ alive: Bool) {
        UserDefaults.standard.set(alive, forKey: FlightRecorder.aliveKey(for: fileURL))
    }

    @discardableResult
    private func flushSync(force: Bool) -> Bool {
        let cutoff = Date().addingTimeInterval(-window)
        let allEntries = memory.snapshot()
        let breadcrumbs = SwiftMoLogger.breadcrumbs()
        let networkEvents = NetworkEventStore.shared.snapshot()
        let signpostEvents = SignpostEventStore.shared.snapshot()
        let vitals = VitalsHistoryStore.shared.snapshot()
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
            breadcrumbs: breadcrumbs,
            networkEvents: networkEvents.filter { $0.startedAt >= cutoff },
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
