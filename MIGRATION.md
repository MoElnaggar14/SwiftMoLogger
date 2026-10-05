# Migrating to SwiftMoLogger 4.0

4.0 removes every singleton and the static `SwiftMoLogger.*` facade. You create
one `LogEnvironment` at your composition root and inject it, or just the piece a
component needs. The upgrade is mechanical; this guide maps every old call.

## Why

The global registry made SwiftMoLogger easy to start with, but it caused three problems:

- **Tests interfered with each other.** Every suite shared one registry, so
  they couldn't run in parallel.
- **Frameworks leaked into the host app.** A framework using SwiftMoLogger
  logged into the app's global engines.
- **Dependencies were hidden.** You couldn't tell from a type's API that it
  logged, or where its logs went.

With injection, all three are explicit and swappable.

## Requirements

Xcode 16 or later. The library now compiles in the Swift 6 language mode; your app can stay on Swift 5 mode.

## 1. Build the environment once

```swift
import SwiftMoLogger

@main
struct ShopApp: App {
    private let logging = LogEnvironment()

    init() {
        logging.registry.addEngine(MemoryLogEngine())
        // FileLogEngine's init throws (e.g. an unwritable directory); don't trap at launch.
        if let file = try? FileLogEngine(fileURL: logsURL) {
            logging.registry.addEngine(RedactingLogEngine(wrapping: file))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(checkout: CheckoutService(log: logging.logger))
        }
    }
}
```

`LogEnvironment` owns:
- `registry`, the engine registry.
- `logger`, a `MoLogger` bound to that registry.
- `stream`, a live `AsyncStream` of entries.
- `breadcrumbs`, `networkEvents`, `signposts` and `vitals`, the diagnostics stores.
- `signposter`, which measures spans.

## 2. Inject a logger instead of calling the facade

```swift
// 3.x
final class CheckoutService {
    func pay() { SwiftMoLogger.info("Paying", tag: .business) }
}

// 4.0
final class CheckoutService {
    private let log: MoLogger
    init(log: MoLogger) { self.log = log.with(tag: .business) }
    func pay() { log.info("Paying") }
}
```

## API map

| 3.x | 4.0 |
| --- | --- |
| `SwiftMoLogger.info/notice/error/critical/fault/trace/debug(…)` | `logger.info/notice/error/critical/fault/trace/debug(…)` |
| `SwiftMoLogger.warn(…)` | `logger.warning(…)` |
| `SwiftMoLogger.log(level, …)` | `logger.log(level, …)` |
| `SwiftMoLogger.crash(…)` | `logger.critical(…, tag: .crash)` |
| `MoLogger.shared`, `EngineRegistry.shared` | `environment.logger`, `environment.registry` |
| `SwiftMoLogger.addEngine / removeEngine / allEngines / engineCount` | `registry.addEngine / removeEngine / allEngines / engineCount` |
| `SwiftMoLogger.minimumLevel` | `registry.minimumLevel` |
| `SwiftMoLogger.reset()` | `registry.reset()` (keeps the environment's stream) or a new `LogEnvironment` |
| `SwiftMoLogger.enableRedaction(at:)` | `registry.enableRedaction(at:)` |
| `SwiftMoLogger.withContext(meta) { … }` | `LogContext.with(meta) { … }` |
| `SwiftMoLogger.currentContext` | `LogContext.current` |
| `SwiftMoLogger.withTrace(ctx) { … }` | `ctx.run { … }` |
| `SwiftMoLogger.breadcrumb(…)` / `breadcrumbs()` / `clearBreadcrumbs()` | `environment.breadcrumbs.record(…)` / `.snapshot()` / `.clear()` |
| `SwiftMoLogger.stream(bufferSize:)` | `environment.stream.subscribe(bufferSize:)` |
| `SwiftMoLogger.publisher()` | `let c = CombineLogPublisher(); registry.addEngine(c); c.publisher` |
| `LogSignpost.measure / measureAsync / Interval(name:) / event` | `environment.signposter.measure / measureAsync / makeInterval(_:) / event` |
| `LogTagged` (`logInfo`, `logError`, …) | `logger.with(tag:)` |
| `FlightRecorder(fileURL:…)` | `FlightRecorder(environment:fileURL:…)`; read `recorder.crashedSession` |
| `MetricKitCrashReporter()` | `MetricKitCrashReporter(logger:)` |
| `AppVitalsMonitor.shared` | `AppVitalsMonitor(logger:history:)` |
| `BugReporter(memoryEngine:appName:)` | `BugReporter(environment:memoryEngine:vitalsMonitor:appName:)` |
| `LiveSink()` | `LiveSink(statusLogger:)` (optional) |
| `DiagnosticsHubView()` / `HubViewModel()` | `DiagnosticsHubView(environment:)` / `HubViewModel(environment:)` |
| `LogConsoleView()` / `LogConsoleViewModel()` | `LogConsoleView(stream:)` / `LogConsoleViewModel(stream:)` |
| `NetworkLogger.install(on:)` / `installOnSharedSession()` | `URLSession(configuration:delegate: NetworkLogger(environment:), delegateQueue:)` or `session.data(for:delegate:)` |
| Automatic `traceparent` injection | `request.addTraceparentHeader()` inside `TraceContext.run` |
| `URLRequest.excludeFromNetworkLogging()` | not needed: only sessions you give a `NetworkLogger` are logged |
| `SwiftMoLogHandler(label:)`, `.bootstrap()` | `SwiftMoLogHandler(label:logger:)`, `.bootstrap(logger:)` |
| `#log("msg")` | `#log(logger, "msg")` |
| `#measure("name") { … }` | `#measure(signposter, "name") { … }` |
| `@AutoLog` | unchanged, but the type needs a `logger: MoLogger` property |
| `SwiftMoLogger.installRecorder()` | `let (logging, logs) = LogEnvironment.recording()` or `MoLogger.recording()` |

## Safer defaults

- **System log privacy.** `SystemLogger` now defaults to `.privateInRelease`: readable while debugging, `<private>` in release builds' unified log (and so in sysdiagnose archives). Pass `privacy: .public` to keep 3.x behaviour.
- **No traps on bad input.** These initializers are failable, because their input usually comes from outside the app:

  ```swift
  // 3.x                                         // 4.0
  TraceContext(traceID: id, spanID: span)        TraceContext(traceID: id, spanID: span)   // TraceContext?
  SentryLogEngine(dsn: dsn)                      if let sentry = SentryLogEngine(dsn: dsn) { … }
  WebSocketTailEngine(url: url)                  if let tail = WebSocketTailEngine(url: url) { … }
  ```

## Network logging

`URLProtocol` subclasses are instantiated by the URL loading system, so they
can't receive dependencies. Network capture is now a `URLSessionTaskDelegate`
you inject:

```swift
let network = NetworkLogger(environment: logging)
let session = URLSession(configuration: .default, delegate: network, delegateQueue: nil)

// Or one request on any session:
let (data, _) = try await URLSession.shared.data(for: request, delegate: network)
```

It only observes: it doesn't buffer bodies, alter requests or interfere with
redirects. Traffic from SDKs whose sessions you don't control is no longer
captured.

## Tests

```swift
final class CheckoutTests: XCTestCase {
    func testPaymentIsLogged() {
        let (log, logs) = MoLogger.recording()
        CheckoutService(log: log).pay()
        XCTAssertLogged(.info, contains: "Paying", in: logs)
    }
}
```

Each test owns its environment, so suites can run in parallel.
