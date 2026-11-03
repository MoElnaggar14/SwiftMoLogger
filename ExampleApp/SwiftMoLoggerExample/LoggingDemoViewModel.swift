import SwiftUI
import SwiftMoLogger
import SwiftMoLoggerNetwork
import SwiftMoLoggerDiagnostics

@MainActor
final class LoggingDemoViewModel: ObservableObject {
    @Published var memoryCounters: (total: Int, warnings: Int, errors: Int) = (0, 0, 0)
    @Published var breadcrumbCount: Int = 0
    @Published var engineCount: Int = 0
    @Published var lastVitals: AppVitalsMonitor.Sample?

    let bugReporter: BugReporter
    /// Entries recovered by the flight recorder if the previous run crashed.
    let recoveredEntryCount: Int?

    private let logging: LogEnvironment
    private let logger: MoLogger
    private let memory: MemoryLogEngine
    private let vitals: AppVitalsMonitor
    private let session: URLSession
    private let network: NetworkLogger

    #if DEBUG
    private var liveSink: LiveSink?
    #endif
    private var task: Task<Void, Never>?

    init(dependencies: AppDependencies) {
        self.logging = dependencies.logging
        self.logger = dependencies.logging.logger
        self.memory = dependencies.memory
        self.vitals = dependencies.vitals
        self.session = dependencies.session
        self.network = dependencies.network
        self.recoveredEntryCount = dependencies.flightRecorder.crashedSession?.entries.count
        self.bugReporter = BugReporter(
            environment: dependencies.logging,
            memoryEngine: dependencies.memory,
            vitalsMonitor: dependencies.vitals,
            appName: "SwiftMoLoggerExample"
        )
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.refresh() }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func clearAll() {
        logging.breadcrumbs.clear()
        memory.clear()
        for engine in logging.registry.allEngines() {
            if let grouping = engine as? ErrorGroupingEngine { grouping.clear() }
        }
        refresh()
    }

    /// Runs through the `NetworkLogger`-instrumented session. Inside
    /// `TraceContext.run { … }` the request also carries a W3C
    /// `traceparent` header; outside one, `addTraceparentHeader()` is a no-op.
    func fetch(_ url: URL) async -> String {
        var request = URLRequest(url: url)
        request.addTraceparentHeader()
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return "\(status) · \(data.count) B"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    /// `NetworkLogger.data(for:on:)` on the session whose own delegate is the
    /// same logger. The Hub should show the request once, with its response body.
    func fetchCapturingResponseBody(_ url: URL) async -> String {
        await summarize { try await network.data(for: URLRequest(url: url), on: session) }
    }

    /// The per-request delegate on a session that has none. Logs the request
    /// and response; only the request body is captured.
    func fetchWithPerRequestDelegate(_ url: URL) async -> String {
        await summarize { try await URLSession.shared.data(for: URLRequest(url: url), delegate: network) }
    }

    private func summarize(_ load: () async throws -> (Data, URLResponse)) async -> String {
        do {
            let (data, response) = try await load()
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return "\(status) · \(data.count) B"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    /// Shows private values in every engine while you debug. Reads `false` in
    /// release builds whatever is set.
    var revealsPrivateValues: Bool {
        get { logging.registry.revealsPrivateValues }
        set {
            objectWillChange.send()
            logging.registry.revealsPrivateValues = newValue
        }
    }

    /// LiveSink streams unencrypted logs to the local network, so it only exists in
    /// DEBUG builds (and `Info-Debug.plist` holds its Bonjour keys).
    func startLiveSink() {
        #if DEBUG
        guard liveSink == nil else { return }
        let sink = LiveSink(statusLogger: logger)
        do {
            try sink.start()
            logging.registry.addEngine(sink)
            liveSink = sink
            logger.notice("LiveSink advertising on Bonjour", tag: .Development.debug)
        } catch {
            logger.error(error, tag: .Development.debug)
        }
        #endif
    }

    func stopLiveSink() {
        #if DEBUG
        guard let sink = liveSink else { return }
        sink.stop()
        logging.registry.removeEngine(id: sink.engineID)
        liveSink = nil
        #endif
    }

    private func refresh() {
        memoryCounters = memory.counters()
        breadcrumbCount = logging.breadcrumbs.snapshot().count
        engineCount = logging.registry.engineCount
        lastVitals = vitals.lastSample
    }
}
