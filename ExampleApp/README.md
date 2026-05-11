# SwiftMoLoggerExample

A minimal SwiftUI iOS app that exercises every headline v3 feature.

## What it shows

Three tabs:

| Tab | What it shows |
|---|---|
| **Demo** | Buttons that emit structured logs (info / warn / error / debug) with tags + metadata, record breadcrumbs, run `LogSignpost.measure` spans, and clear everything. Live counters for the in-memory engine + breadcrumb store. |
| **Console** | The bundled `LogConsoleView` from `SwiftMoLoggerUI` — live tail, level filter, search, pause, auto-scroll. |
| **Hub** | The headline feature: `DiagnosticsHubView` with timeline scrubber, network waterfall, signpost flame graph, vitals charts, and breadcrumb trail. |

## Run

```bash
open ExampleApp/SwiftMoLoggerExample.xcodeproj
```

…then `⌘R`. The project depends on the local `SwiftMoLogger` and `SwiftMoLoggerUI` products.

## Wiring (see `SwiftMoLoggerExampleApp.swift`)

```swift
init() {
    SwiftMoLogger.addEngine(MemoryLogEngine(capacity: 2_000))
    SwiftMoLogger.enableRedaction()
    SwiftMoLogger.info("Example app launching", tag: .System.lifecycle)
}
```

That's it. The Hub picks up everything else (network events, signposts, vitals) on its own — those stores live in the core target and every instrumentation feature records into them.

## Extending the example

To exercise the rest of the package, add any of:

```swift
import SwiftMoLoggerNetwork       // auto URLSession capture
import SwiftMoLoggerRemote        // Sentry / Datadog / Loki shippers
import SwiftMoLoggerDiagnostics   // LiveSink (Bonjour), AppVitalsMonitor, BugReporter
import SwiftMoLoggerTesting       // XCTAssertLogged + RecordingLogEngine
import SwiftMoLoggerSugar         // #log / #measure / @AutoLog macros
```

All seven products are library targets in the same package — just drop them into the example's target dependencies in Xcode and import.
