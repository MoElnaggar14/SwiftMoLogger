import SwiftUI
import SwiftMoLogger
import SwiftMoLoggerNetwork
import SwiftMoLoggerDiagnostics

@main
struct SwiftMoLoggerExampleApp: App {
    static let flightRecorder = FlightRecorder()

    init() {
        Self.configureLogging()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    /// Every line below maps to a tab in `ContentView`, so readers can
    /// scan boot-to-screen and see exactly what each feature costs.
    static func configureLogging() {
        // 1. Engines: an in-memory ring for the Console + Hub, plus a
        //    SystemLogger mirror so Console.app still works. The system
        //    engine is wrapped in `ErrorGroupingEngine` so identical-shape
        //    error spam collapses into a single fingerprinted record.
        SwiftMoLogger.addEngine(MemoryLogEngine(capacity: 2_000))
        SwiftMoLogger.addEngine(ErrorGroupingEngine(wrapping: SystemLogger()))

        // 2. Wrap engine #0 with the PII redactor so emails, tokens, and
        //    credit-card numbers never leave the device in cleartext.
        SwiftMoLogger.enableRedaction()

        // 4. Sampling + rate-limit on a disk engine so devices in the
        //    field generate a manageable amount of file I/O.
        let logFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.log")
        if let file = try? FileLogEngine(fileURL: logFile) {
            let sampled = SamplingLogEngine(
                wrapping: file,
                strategy: .perLevel(rates: [
                    .trace: 0.1, .debug: 0.1, .info: 0.5,
                    .notice: 1, .warning: 1, .error: 1, .critical: 1, .fault: 1
                ])
            )
            SwiftMoLogger.addEngine(RateLimitingLogEngine(wrapping: sampled, permitsPerSecond: 200))
        }

        // 5. Auto-instrumented URLSession capture for the Network tab.
        NetworkLogger.installOnSharedSession()

        // 6. App vitals (memory / CPU / FPS / thermal / battery) every
        //    5 s — feeds the Hub's vitals charts.
        AppVitalsMonitor.shared.start(interval: 5)

        // 7. Flight recorder: rolling 2-minute black box flushed to disk
        //    every 2 s for post-crash forensics. Held in a static so the
        //    DispatchSource timer outlives this init.
        Self.flightRecorder.start()

        SwiftMoLogger.info(
            "Example app launching",
            tag: .System.lifecycle,
            metadata: [
                "engines": .int(Int64(SwiftMoLogger.engineCount)),
                "build": .string(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
            ]
        )
        SwiftMoLogger.breadcrumb("app launched", category: .lifecycle)
    }
}

