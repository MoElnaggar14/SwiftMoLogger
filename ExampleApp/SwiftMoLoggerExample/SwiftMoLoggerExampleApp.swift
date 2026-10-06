import SwiftUI
import SwiftMoLogger
import SwiftMoLoggerNetwork
import SwiftMoLoggerDiagnostics

@main
struct SwiftMoLoggerExampleApp: App {
    /// The composition root. SwiftMoLogger 4 has no singletons: every
    /// logging object is built exactly once, here, and handed down through
    /// initializers.
    private let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let dependencies = AppDependencies()
        Self.configureLogging(dependencies)
        self.dependencies = dependencies
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS can terminate a suspended app without warning: write buffered logs first.
            if phase == .background { dependencies.logging.registry.flush() }
        }
    }

    /// Every line below maps to a tab in `ContentView`, so readers can
    /// scan boot-to-screen and see exactly what each feature costs.
    static func configureLogging(_ dependencies: AppDependencies) {
        let logging = dependencies.logging
        let registry = logging.registry

        // 1. Engines. `LogEnvironment()` already registered a default
        //    `SystemLogger` (so Console.app still works) and the live
        //    `LogStream` that feeds the Console tab. Wrap the system engine
        //    in `ErrorGroupingEngine` so identical-shape error spam collapses
        //    into a single fingerprinted record, and add an in-memory ring
        //    for the Demo counters and bug reports.
        //
        // 2. PII redaction: every engine that shows or stores entries is
        //    wrapped in `RedactingLogEngine`, so emails, tokens, and
        //    credit-card numbers never appear in cleartext.
        if let system = registry.allEngines().first(where: { $0 is SystemLogger }) {
            registry.replaceEngine(id: system.engineID) { engine in
                ErrorGroupingEngine(wrapping: RedactingLogEngine(wrapping: engine))
            }
        }
        registry.replaceEngine(id: logging.stream.engineID) { engine in
            RedactingLogEngine(wrapping: engine)
        }
        registry.addEngine(RedactingLogEngine(wrapping: dependencies.memory))

        // 3. Sampling + rate-limit on a disk engine so devices in the
        //    field generate a manageable amount of file I/O.
        let logFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.log")
        if let file = try? FileLogEngine(fileURL: logFile) {
            let sampled = SamplingLogEngine(
                wrapping: RedactingLogEngine(wrapping: file),
                strategy: .perLevel(rates: [
                    .trace: 0.1, .debug: 0.1, .info: 0.5,
                    .notice: 1, .warning: 1, .error: 1, .critical: 1, .fault: 1
                ])
            )
            registry.addEngine(RateLimitingLogEngine(wrapping: sampled, permitsPerSecond: 200))
        }

        // 4. Network capture for the Network tab: `dependencies.session` was
        //    created with a `NetworkLogger` delegate (see `AppDependencies`).

        // 5. App vitals (memory / CPU / FPS / thermal / battery) every
        //    5 s — feeds the Hub's vitals charts.
        dependencies.vitals.start(interval: 5)

        // 6. Flight recorder: rolling 2-minute black box flushed to disk
        //    every 2 s for post-crash forensics. `dependencies` (and so the
        //    recorder) lives as long as the app.
        dependencies.flightRecorder.start()

        let lifecycle = logging.logger.with(tag: .System.lifecycle)
        lifecycle.info(
            "Example app launching",
            metadata: [
                "engines": .int(Int64(registry.engineCount)),
                "build": .string(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
            ]
        )
        if let crashed = dependencies.flightRecorder.crashedSession {
            lifecycle.warning(
                "Recovered \(crashed.entries.count) entries from a crashed session",
                metadata: ["breadcrumbs": .int(Int64(crashed.breadcrumbs.count))]
            )
        }
        logging.breadcrumbs.record("app launched", category: .lifecycle)
    }
}

/// Long-lived logging objects, built once by the `App` and injected into
/// the views and view models that need them.
struct AppDependencies {
    /// Registry, logger, live stream, and the diagnostics stores.
    let logging: LogEnvironment
    /// In-memory ring for the Demo tab's counters and the bug-report bundle.
    let memory: MemoryLogEngine
    /// A session whose every task is logged by a `NetworkLogger` delegate
    /// (request/response entries, breadcrumbs, and Hub waterfall events).
    let session: URLSession
    let vitals: AppVitalsMonitor
    let flightRecorder: FlightRecorder

    /// Builds the objects without starting anything; the `App` starts them
    /// in `configureLogging(_:)`, previews just use them as-is.
    init(logging: LogEnvironment = LogEnvironment()) {
        self.logging = logging
        self.memory = MemoryLogEngine(capacity: 2_000)
        self.session = URLSession(
            configuration: .default,
            // Request bodies show in the Hub's detail view in debug builds only.
            delegate: NetworkLogger(environment: logging, bodies: .debugOnly(maxBytes: 16 * 1_024)),
            delegateQueue: nil
        )
        self.vitals = AppVitalsMonitor(logger: logging.logger, history: logging.vitals)
        // Redact before anything touches the disk: the crash file can outlive the session.
        self.flightRecorder = FlightRecorder(environment: logging, redactor: Redactor())
    }
}
