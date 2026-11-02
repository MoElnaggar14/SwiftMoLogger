# Migrating from 4.x to 5.0

5.0 makes log messages private by default, as in `os.Logger` ([#48](https://github.com/MoElnaggar14/SwiftMoLogger/issues/48)), and removes deprecated API ([#49](https://github.com/MoElnaggar14/SwiftMoLogger/issues/49)). A forgotten privacy marker now hides a value instead of leaking it to every engine.

```swift
log.info("Signed in \(email) on \(device)")              // "Signed in <private> on <private>"
log.info("Opened \(screen, privacy: .public)")           // "Opened Settings"
log.info("Retry \(attempt) of \(limit), ok: \(isOK)")    // "Retry 2 of 5, ok: false"
log.info("Step \(step)")                                 // "Step checkout"  (CheckoutStep: LogPublicValue)
log.info(LogMessage(verbatim: text))                    // a String you know is safe, shown as is
```

| Change | Who notices | How to migrate |
|---|---|---|
| An interpolation without `privacy:` renders `<private>`, unless it's a number, `Bool` or `LogPublicValue` | output only, no build error | Run `audit_logging.py --privacy` to list them. Add `privacy: .public` where the value is safe, or conform the type to `LogPublicValue` |
| `String` values as the message (`log.info(text)`) don't compile | build error, with the fix in the message | `"\(text)"` hides the text, `LogMessage(verbatim: text)` shows it. App wrappers take a `LogMessage` |
| `"a" + b` as a message doesn't compile (`+` makes a `String`) | build error | `"a\(b)"` |
| `#log` takes a `LogMessage` and a non-optional `MoLogger` | build error for `String` values only | as above |
| `error(_:)` hides `localizedDescription` (the `error_type` metadata stays) | output only | `log.error("\(error.localizedDescription, privacy: .public)")` to show it |
| `breadcrumbs.record(_:)` and `signposter.event(_:message:)` take a `LogMessage` under the same rule | output, or a build error for `String` values | as above |
| `revealsPrivateValues` reads `false` in release builds | output only, release only | none; use a Debug-like configuration for QA builds that need private values |
| `EngineRegistry.getAllEngines()` is removed | build error | `allEngines()` (the audit's `migrate` finding says so) |

**Step by step**

1. Before upgrading, on 4.6: run `python3 plugin/skills/swiftmologger/scripts/audit_logging.py --privacy path/to/YourApp`. Each `[privacy]` line is an interpolation that renders `<private>` in 5.0. `--fix-privacy` marks the safe ones (`.rawValue`, names ending in `count`, `index`, `ID` or `Id`) `privacy: .public` and lists the rest.
2. Settle each remaining line: `privacy: .public` if the value is safe to show, `privacy: .private` to say it's hidden on purpose. Conform enums of screens or states to `LogPublicValue` once instead of marking every call site.
3. Upgrade and build. Fix each `String` message the compiler lists, choosing `"\(text)"` or `LogMessage(verbatim: text)`.
4. Run `audit_logging.py` without flags: it reports `getAllEngines()` and any other removed API.

**Unchanged:** engines, `LogEntry` (its `message` is still the rendered `String`), metadata (privacy covers the message only; metadata goes through `RedactingLogEngine`), and `SystemLogger`'s `.privateInRelease` default.

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

