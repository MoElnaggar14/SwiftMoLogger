import SwiftUI
import SwiftMoLogger

/// Entry point — wires every interesting engine up front so the
/// Diagnostics Hub has real signals to show.
@main
struct SwiftMoLoggerExampleApp: App {
    init() {
        // Keep a generous in-memory ring buffer so the Hub timeline has
        // something to display after a few minutes of use.
        SwiftMoLogger.addEngine(MemoryLogEngine(capacity: 2_000))

        // PII / secret scrubber on top of the default SystemLogger.
        SwiftMoLogger.enableRedaction()

        SwiftMoLogger.info("Example app launching", tag: .System.lifecycle, metadata: [
            "engines": .int(Int64(SwiftMoLogger.engineCount))
        ])
        SwiftMoLogger.breadcrumb("app launched", category: .lifecycle)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
