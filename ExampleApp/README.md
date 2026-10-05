# SwiftMoLoggerExample

End-to-end SwiftUI showcase that exercises every product in the v4 package — Core, UI, Network, Diagnostics, Sugar (macros), and Remote — so you can sanity-check the whole pipeline before recommending it to other apps.

## Tabs

| Tab | What it shows |
|---|---|
| **Demo** | Every level (`trace`/`debug`/`info`/`notice`/`warning`/`error`/`critical`/`fault`) on an injected `MoLogger`, child loggers (`with(tag:)` / `with(metadata:)`), breadcrumbs, `Signposter` spans, the `#log`/`#measure`/`@AutoLog` macros, ambient `LogContext.with { … }`, distributed tracing via `TraceContext.generate().run { … }`, PII redaction, and live error-grouping. |
| **Console** | Bundled `LogConsoleView(stream:)` — live tail, level filter, search, pause, auto-scroll. |
| **Hub** | `DiagnosticsHubView(model:)` over the app's `LogEnvironment`: timeline scrubber, network waterfall, signpost flame graph, vitals charts, breadcrumb trail. |
| **Network** | A `URLSession` with a `NetworkLogger(environment:)` delegate (200 / 404 / 500 / inside-a-trace requests with a `traceparent` header) and sensitive-header scrubbing. |
| **Diagnostics** | Live `AppVitalsMonitor` sample, `FlightRecorder` status, one-tap `BugReporter` bundle (with `ShareLink`), Bonjour `LiveSink` toggle, plus snippets for `MetricKitCrashReporter` and the remote shippers. |
| **About** | Full feature matrix — handy talking points when pitching the library. |

## Run

```bash
open ExampleApp/SwiftMoLoggerExample.xcodeproj
```

…then `⌘R`. The project's six target dependencies (`SwiftMoLogger`, `SwiftMoLoggerUI`, `SwiftMoLoggerNetwork`, `SwiftMoLoggerDiagnostics`, `SwiftMoLoggerSugar`, `SwiftMoLoggerRemote`) all resolve from the workspace's local SPM checkout.

Deployment target: **iOS 17**. The library still ships against iOS 16 / macOS 13.

## Boot wiring — `SwiftMoLoggerExampleApp.swift`

SwiftMoLogger 4 has no singletons or static facade. The `App` builds one `LogEnvironment` (inside `AppDependencies`), configures it in `configureLogging(_:)`, and passes it — or narrower pieces such as `MoLogger`, `Signposter`, `BreadcrumbStore` — down through initializers:

```swift
let logging = LogEnvironment()                    // registry, logger, stream, stores
let memory = MemoryLogEngine(capacity: 2_000)
let session = URLSession(configuration: .default,
                         delegate: NetworkLogger(environment: logging),
                         delegateQueue: nil)
let vitals = AppVitalsMonitor(logger: logging.logger, history: logging.vitals)
let recorder = FlightRecorder(environment: logging)

logging.registry.replaceEngine(id: systemLoggerID) { ErrorGroupingEngine(wrapping: RedactingLogEngine(wrapping: $0)) }
logging.registry.addEngine(RedactingLogEngine(wrapping: memory))

let sampled = SamplingLogEngine(wrapping: RedactingLogEngine(wrapping: file), strategy: .perLevel(rates: […]))
logging.registry.addEngine(RateLimitingLogEngine(wrapping: sampled, permitsPerSecond: 200))

vitals.start(interval: 5)
recorder.start()

ContentView(dependencies: dependencies)            // injected, not global
```

## Plugging this into your own app

Add the dependency and pick the products you want:

```swift
.package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "4.0.0")
```

```swift
.product(name: "SwiftMoLogger", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerUI", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerNetwork", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerDiagnostics", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerSugar", package: "SwiftMoLogger"),
.product(name: "SwiftMoLoggerRemote", package: "SwiftMoLogger"),
```

Then mirror `AppDependencies` + `configureLogging(_:)` above in your `App.init`, and inject `logging.logger` (or a child of it) into each component. That's it.
