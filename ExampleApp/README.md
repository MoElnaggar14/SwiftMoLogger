# SwiftMoLoggerExample

End-to-end SwiftUI showcase that exercises every product in the v3 package — Core, UI, Network, Diagnostics, Sugar (macros), and Remote — so you can sanity-check the whole pipeline before recommending it to other apps.

## Tabs

| Tab | What it shows |
|---|---|
| **Demo** | Every level (`trace`/`debug`/`info`/`notice`/`warn`/`error`/`critical`/`fault`), breadcrumbs, signposts, the `#log`/`#measure`/`@AutoLog` macros, ambient `withContext { … }`, distributed tracing via `withTrace { … }`, PII redaction, and live error-grouping. |
| **Console** | Bundled `LogConsoleView` — live tail, level filter, search, pause, auto-scroll. |
| **Hub** | `DiagnosticsHubView`: timeline scrubber, network waterfall, signpost flame graph, vitals charts, breadcrumb trail. |
| **Network** | Auto-instrumented `URLSession.shared` (200 / 404 / 500 / inside-a-trace requests) flowing through `NetworkLoggingProtocol` with sensitive-header scrubbing. |
| **Diagnostics** | Live `AppVitalsMonitor` sample, `FlightRecorder` status, one-tap `BugReporter` bundle (with `ShareLink`), Bonjour `LiveSink` toggle, plus snippets for `MetricKitCrashReporter` and the remote shippers. |
| **About** | Full feature matrix — handy talking points when pitching the library. |

## Run

```bash
open ExampleApp/SwiftMoLoggerExample.xcodeproj
```

…then `⌘R`. The project's six target dependencies (`SwiftMoLogger`, `SwiftMoLoggerUI`, `SwiftMoLoggerNetwork`, `SwiftMoLoggerDiagnostics`, `SwiftMoLoggerSugar`, `SwiftMoLoggerRemote`) all resolve from the workspace's local SPM checkout.

Deployment target: **iOS 17**. The library still ships against iOS 16 / macOS 13.

## Boot wiring — `SwiftMoLoggerExampleApp.swift`

Every interesting engine + monitor is wired in `configureLogging()` so you can scan one function and see the entire integration surface:

```swift
SwiftMoLogger.addEngine(MemoryLogEngine(capacity: 2_000))
SwiftMoLogger.addEngine(ErrorGroupingEngine(wrapping: SystemLogger()))
SwiftMoLogger.enableRedaction()

let sampled = SamplingLogEngine(wrapping: file, strategy: .perLevel(rates: […]))
SwiftMoLogger.addEngine(RateLimitingLogEngine(wrapping: sampled, permitsPerSecond: 200))

NetworkLogger.installOnSharedSession()
AppVitalsMonitor.shared.start(interval: 5)
FlightRecorder().start()
```

## Plugging this into your own app

Add the dependency and pick the products you want:

```swift
.package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "3.0.0")
```

```swift
.product(name: "SwiftMoLogger", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerUI", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerNetwork", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerDiagnostics", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerSugar", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerRemote", package: "SwiftMoLogger"),
```

Then mirror `configureLogging()` above in your `App.init`. That's it.
