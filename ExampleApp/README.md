# SwiftMoLoggerExample

End-to-end SwiftUI showcase that exercises every product in the v5 package — Core, UI, Network, Diagnostics, Sugar (macros), and Remote — so you can sanity-check the whole pipeline before recommending it to other apps.

## Tabs

| Tab | What it shows |
|---|---|
| **Demo** | Private-by-default interpolation (with a DEBUG-only reveal toggle), every level (`trace`/`debug`/`info`/`notice`/`warning`/`error`/`critical`/`fault`) on an injected `MoLogger`, child loggers (`with(tag:)` / `with(metadata:)`), breadcrumbs, `Signposter` spans, the `#log`/`#measure`/`@AutoLog` macros, ambient `LogContext.with { … }`, distributed tracing via `TraceContext.generate().run { … }`, PII redaction, and live error-grouping. |
| **Console** | Bundled `LogConsoleView(stream:)` — live tail, level filter, search, pause, auto-scroll. |
| **Hub** | `DiagnosticsHubView(model:)` over the app's `LogEnvironment`: timeline scrubber, network waterfall, signpost flame graph, vitals charts, breadcrumb trail. |
| **Network** | A `URLSession` with a `NetworkLogger(environment:)` delegate (200 / 404 / 500 / inside-a-trace requests with a `traceparent` header), response bodies with `network.data(for:on:)`, a per-request delegate, and sensitive-header scrubbing. |
| **Diagnostics** | Live `AppVitalsMonitor` sample, `FlightRecorder` status, one-tap `BugReporter` bundle (with `ShareLink`), Bonjour `LiveSink` toggle, plus snippets for `MetricKitCrashReporter` and the remote shippers. |
| **About** | Full feature matrix — handy talking points when pitching the library. |

## Run on the simulator

```bash
open ExampleApp/SwiftMoLoggerExample.xcodeproj
```

Pick an iPhone simulator and press ⌘R. The six products (`SwiftMoLogger`, `SwiftMoLoggerUI`, `SwiftMoLoggerNetwork`, `SwiftMoLoggerDiagnostics`, `SwiftMoLoggerSugar`, `SwiftMoLoggerRemote`) resolve from this checkout (`..`), so your local edits to the library show up immediately. The first build compiles swift-syntax for the macros, which takes a minute. If Xcode asks you to trust the `SwiftMoLoggerMacros` macro, choose **Trust & Enable**.

The Network tab calls httpbin.org, so it needs internet access. Check the vitals charts on a device too, since a simulator's CPU, memory and thermal numbers are your Mac's.

## Run on an iPhone or iPad

1. Select the **SwiftMoLoggerExample** target → Signing & Capabilities → choose your **Team**.
2. If the bundle identifier is taken, change it, e.g. to `com.<you>.SwiftMoLoggerExample`.
3. Connect the device, turn on Developer Mode (Settings → Privacy & Security → Developer Mode), pick the device and press ⌘R.

## Tail the device from your Mac

1. In the Debug build, open **Diagnostics** → turn on **Advertise _swiftmologger._tcp**. Allow the local network prompt on the device.
2. On a Mac on the same Wi-Fi, from the repository root:

   ```bash
   swift run swiftmologger-inspector
   ```

3. Tap around the Demo tab. Each log line appears in the terminal.

The Debug configuration merges `Info-Debug.plist`, which declares `NSLocalNetworkUsageDescription` and `NSBonjourServices`. Release builds have neither key, and the LiveSink section is compiled out (`#if DEBUG`). That's the setup to copy into your own app.

## Let an AI agent read the device's logs

With LiveSink on (step 1 above), the [MCP server](../Tools/swiftmologger-mcp/README.md) gives Claude Code, Codex or Cursor the same live logs:

```bash
swift build -c release --package-path Tools/swiftmologger-mcp
claude mcp add swiftmologger -- "$PWD/Tools/swiftmologger-mcp/.build/release/swiftmologger-mcp"
```

Then ask the agent, for example, "list the devices running SwiftMoLogger, then show the last warnings". Entries reach the agent redacted.

## Device checks

[#59](https://github.com/MoElnaggar14/SwiftMoLogger/issues/59) lists what CI can't check. This app has a control for each one:

| Check | Where |
|---|---|
| Private by default | Demo → **Private by default**. Watch the Console tab, then turn on the reveal toggle. |
| Async network bodies | Network → **Async bodies**, then the Hub's network waterfall. |
| LiveSink and MCP round trip | Diagnostics → **Advertise _swiftmologger._tcp**, then the inspector or the MCP server. |
| MetricKit on iOS 27 | Run on a device, then Xcode → Debug → Simulate MetricKit Payloads. |
| Release build | Edit Scheme → Run → Build Configuration → Release. Private values stay `<private>` and the LiveSink section is gone. |

Requires Xcode 16 or later. Deployment target: **iOS 17**. The library itself supports iOS 16 / macOS 13.

## Boot wiring — `SwiftMoLoggerExampleApp.swift`

SwiftMoLogger has no singletons or static facade. The `App` builds one `LogEnvironment` (inside `AppDependencies`), configures it in `configureLogging(_:)`, and passes it — or narrower pieces such as `MoLogger`, `Signposter`, `BreadcrumbStore` — down through initializers:

```swift
let logging = LogEnvironment()                    // registry, logger, stream, stores
let memory = MemoryLogEngine(capacity: 2_000)
let session = URLSession(configuration: .default,
                         delegate: NetworkLogger(environment: logging),
                         delegateQueue: nil)
let vitals = AppVitalsMonitor(logger: logging.logger, history: logging.vitals)
let recorder = FlightRecorder(environment: logging, redactor: Redactor())

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
.package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "5.0.1")
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
