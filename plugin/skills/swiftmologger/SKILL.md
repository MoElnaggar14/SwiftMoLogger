---
name: swiftmologger
description: Set up and use the SwiftMoLogger 4.x Swift logging package in iOS, macOS, tvOS or watchOS apps — LogEnvironment composition root, injected MoLogger, engines (system, memory, file, Sentry, Datadog, Loki, HTTP), PII redaction, URLSession network logging, Diagnostics Hub, Bonjour live tail (LiveSink), flight recorder, tracing, macros and tests. Use this skill whenever the project imports SwiftMoLogger or depends on it, whenever the user wants to add logging, crash breadcrumbs, remote log shipping, network logging or log redaction to a Swift app, asks how to test what was logged, or is migrating from SwiftMoLogger 3.x (SwiftMoLogger.info, EngineRegistry.shared, MoLogger.shared) — even if they don't name the package.
---

# SwiftMoLogger 4.x

SwiftMoLogger is structured logging with no singletons. You create one `LogEnvironment` at the composition root. It owns an `EngineRegistry` (which filters by level and fans out each entry to the engines), a `logger: MoLogger` bound to that registry, a live `stream`, a `signposter`, and the diagnostics stores (`breadcrumbs`, `networkEvents`, `signposts`, `vitals`). Every other component receives the narrowest piece it needs through its initialiser.

Analogy: the environment is a building's electrical panel. Engines are the circuits (screen, disk, network), decorators such as redaction, sampling and rate limiting are breakers on a circuit, and `MoLogger` values are the wall sockets you hand to each room. No room reaches into the panel.

## Workflow

### 1. Add only the products you need

| Product | Add it when |
| --- | --- |
| `SwiftMoLogger` | Always: core, engines, redaction, sampling, breadcrumbs, tracing, flight recorder, MetricKit |
| `SwiftMoLoggerNetwork` | You want `URLSession` traffic logged (`NetworkLogger`) |
| `SwiftMoLoggerRemote` | You ship logs to Sentry, Datadog, Loki or your own HTTP endpoint |
| `SwiftMoLoggerUI` | You want an in-app `DiagnosticsHubView` or `LogConsoleView` |
| `SwiftMoLoggerDiagnostics` | You want `LiveSink` (Mac live tail), `AppVitalsMonitor`, `BugReporter` or `WebSocketTailEngine` |
| `SwiftMoLoggerSugar` | You want the `#log`, `#measure` and `@AutoLog` macros (adds a swift-syntax build) |
| `SwiftMoLoggerSwiftLog` | Dependencies log through Apple's swift-log and you want those logs in your engines |
| `SwiftMoLoggerTesting` | Test targets only |

```swift
.package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "4.0.0")
```

### 2. Build the environment once and inject loggers

```swift
import SwiftMoLogger

@main
struct ShopApp: App {
    private let logging = LogEnvironment()

    init() {
        LoggingSetup.configure(logging)            // engines; see step 3
    }

    var body: some Scene {
        WindowGroup { RootView(checkout: CheckoutService(log: logging.logger)) }
    }
}

final class CheckoutService {
    private let log: MoLogger
    init(log: MoLogger) { self.log = log.with(tag: .business).with(metadata: ["component": "checkout"]) }

    func paymentFailed(orderID: String, error: Error) {
        log.error("Payment failed", metadata: ["order_id": .string(orderID)])
        log.error(error)                           // adds error_type / error metadata
    }
}
```

Follow these rules:
- There is no static API: never write `SwiftMoLogger.info(...)`, `MoLogger.shared` or `EngineRegistry.shared`. Those were removed in 4.0. Don't create a global `let logger = …` to get around this, because it brings back the hidden dependency that 4.0 removed and makes tests share state.
- Inject the narrowest dependency. A service takes a `MoLogger`, a view model that leaves breadcrumbs takes a `BreadcrumbStore`, and code that measures takes a `Signposter`. Only the composition root, `DiagnosticsHubView`, `FlightRecorder`, `NetworkLogger(environment:)` and `BugReporter` take the whole `LogEnvironment`.
- `MoLogger` is a cheap `Sendable` value. Specialise it per component with `with(tag:)` and `with(metadata:)`.
- A new `LogEnvironment` starts with a `SystemLogger` (os.log) already registered. You don't need to add one.
- A framework or SDK should accept a `MoLogger` from its host app rather than create its own environment, unless it deliberately keeps its logs separate.

### 3. Choose engines for debug vs release

The core question is: where should each log go, and who can read it there?

| Engine | Debug | Release | Why |
| --- | :-: | :-: | --- |
| `SystemLogger` (default, `.privateInRelease`) | ✓ | ✓ | Messages show as `<private>` in release sysdiagnose. Keep this default unless the logs contain no user data. |
| `MemoryLogEngine(capacity:)` | ✓ | ✓ | A cheap ring buffer that `BugReporter` and the console read. |
| `FileLogEngine(fileURL:maxFileSizeBytes:maxRotatedFiles:protection:)` | ✓ | wrap with redaction | It persists to disk. Its init `throws`. Pass `protection: .completeUnlessOpen` when logs may hold personal data; never `.complete` if the app logs in the background. |
| `FlightRecorder(environment:redactor:)` | ✓ | ✓ with `redactor:` | Keeps a crash black box in Caches. |
| Sentry / Datadog / Loki / `HTTPLogShipper` | usually off | ✓ wrapped in `RedactingLogEngine` | Sends data off the device. Declare it in the app's privacy manifest and App Store privacy details. |
| `LiveSink` | ✓ only | ✗ | Streams unencrypted, unauthenticated logs to anyone on the Wi-Fi. |
| `DiagnosticsHubView` | ✓ / internal builds | hide | It is a developer tool. |

Starter configuration:

```swift
enum LoggingSetup {
    static func configure(_ logging: LogEnvironment) {
        let redactor = Redactor()
        logging.registry.addEngine(MemoryLogEngine(capacity: 1_000))

        #if DEBUG
        logging.registry.minimumLevel = .trace
        #else
        logging.registry.minimumLevel = .info
        // dsn is a URL; the init returns nil for a malformed DSN.
        if let dsn = URL(string: Config.sentryDSN),
           let sentry = SentryLogEngine(dsn: dsn, release: Config.version, environment: "production") {
            logging.registry.addEngine(RedactingLogEngine(wrapping: sentry, redactor: redactor))
        }
        #endif
    }
}
```

Keep these facts in mind:
- `logger.debug(…)` is compiled out of release builds of the package (`#if DEBUG`), but `trace` is not. Gate verbose logs with `registry.minimumLevel`, which filters before any allocation.
- Messages are autoclosures, so expensive string building is skipped when the level is filtered. Metadata isn't an autoclosure, so don't compute heavy metadata on a hot path.
- `SentryLogEngine(dsn:)` and `WebSocketTailEngine(url:)` are failable, and `TraceContext(traceID:spanID:)` returns nil for invalid IDs. Unwrap them; never force-unwrap a value that comes from remote config.
- Don't embed a Datadog API key (`DatadogLogEngine(apiKey:)`) in an App Store binary, because anyone can extract it. Prefer sending logs to your own backend with `HTTPLogShipper(configuration: .init(endpoint:headers:))` and forwarding them from there. If the user insists, use the most restricted key available and say what the risk is.
- Call `logging.registry.flush()` when the scene moves to `.background`, because iOS can terminate a suspended app without warning. A custom engine that buffers should override `flush()`.
- An engine's `engineID` decides replacement: adding an engine with an existing ID replaces the old one. Two shippers to different endpoints both stay registered.

### 4. Privacy and redaction

Treat everything logged as potentially leaving the device: sysdiagnose, files, remote shippers and the live tail.

- Redaction is opt-in. `logging.registry.enableRedaction(at: 0)` wraps the default `SystemLogger` in place. It only covers the engine at that index.
- Wrap every engine that persists or ships data with `RedactingLogEngine(wrapping:redactor:)`, and register the wrapper **instead of** the engine. If the engine is already registered, swap it in place, or the raw copy keeps logging:
  ```swift
  logging.registry.replaceEngine(id: engine.engineID) { RedactingLogEngine(wrapping: $0, redactor: redactor) }
  ```
- The default rules cover JWTs, Bearer/Basic tokens, AWS/GCP keys, emails, card numbers, phone numbers, IPv4 addresses and UUIDs, and they walk metadata recursively. Add rules for app-specific identifiers: `try redactor.add(Redactor.Rule(name: "ssn", pattern: #"\d{3}-\d{2}-\d{4}"#))`.
- Redaction is a safety net, not a licence. Prefer logging IDs over names, emails or free text the user typed.

### 5. Network logging (optional)

```swift
import SwiftMoLoggerNetwork
let network = NetworkLogger(environment: logging)   // a URLSessionTaskDelegate
let session = URLSession(configuration: .default, delegate: network, delegateQueue: nil)
// or one request: try await URLSession.shared.data(for: request, delegate: network)
```

There is no global hook: only sessions and requests you give it are logged. It redacts sensitive headers and secret query items by default. Use `urlRedaction: .withoutQuery` for stricter apps. `.full` (nothing redacted) is for local debugging only.

### 6. Debug tooling (optional)

```swift
#if DEBUG
import SwiftMoLoggerDiagnostics
#endif

#if DEBUG
let sink = LiveSink(statusLogger: logging.logger)
try sink.start()
logging.registry.addEngine(sink)
#endif
```

- On a real iOS device, `LiveSink` needs `NSLocalNetworkUsageDescription` and `NSBonjourServices` = `[_swiftmologger._tcp]`. Put them in the Debug configuration's Info.plist only.
- `start()` refuses to open the listener in release builds unless the sink was created with `LiveSink(statusLogger:allowInRelease: true)`. Use that only for internal QA builds. The registry retains the sink once you've added it.
- The Mac side is `swift run swiftmologger-inspector`, run from a checkout of the package.
- In-app tools: `DiagnosticsHubView(environment: logging)` or `LogConsoleView(stream: logging.stream)`. For vitals charts, run `AppVitalsMonitor(logger: logging.logger, history: logging.vitals).start(interval: 5)`.

For the flight recorder, MetricKit, tracing, breadcrumbs, signposts, task-local context, swift-log and macros, read [references/features.md](references/features.md).

### 7. Testing

Give each test its own environment and inject it, so tests never share state and can run in parallel:

```swift
import Testing
import SwiftMoLoggerTesting

@Test func declinedPaymentIsLogged() async throws {
    let (log, logs) = MoLogger.recording()          // or LogEnvironment.recording()
    try await CheckoutService(log: log).purchase(invalid: true)
    #expect(logs.contains(.error, containing: "declined", tag: .api))
    #expect(logs.count(.fault) == 0)
}
```

When the type under test also takes a `BreadcrumbStore` (or other stores), use `let (logging, logs) = LogEnvironment.recording()`, inject `logging.logger` and `logging.breadcrumbs`, then check `logging.breadcrumbs.snapshot()`.

With XCTest, use `XCTAssertLogged(.error, contains: "declined", tag: .api, in: logs)` and `XCTAssertLogCount(0, atLevel: .fault, in: logs)`. `logs.entries(_:containing:tag:withMetadataKey:)` returns the matching entries for finer checks. Assert on behaviour that matters, such as an error being reported, not on exact message wording.

## Migrating from 3.x

Run the scanner from the app's root. It lists every 3.x call with its 4.0 replacement, and flags release-safety problems (LiveSink outside `#if DEBUG`, missing Bonjour keys, hard-coded Datadog keys):

```bash
python3 <skill-dir>/scripts/audit_logging.py .
```

Then follow [references/migration-3x.md](references/migration-3x.md). The approach: create the `LogEnvironment` first, then replace each `SwiftMoLogger.x(…)` call by injecting a `MoLogger` into its owning type. Work one type at a time, so the app compiles after each step.

## Before you finish

- There is exactly one `LogEnvironment` in the app target, created at the composition root, with no globals or `.shared`.
- Every engine that persists or ships data is wrapped in `RedactingLogEngine`, and the flight recorder gets `redactor:`.
- `LiveSink` and its Info.plist keys exist only in debug builds.
- Remote shippers are declared in the privacy manifest, and no secrets are hard-coded.
- Tests use `MoLogger.recording()` or `LogEnvironment.recording()`.
- `audit_logging.py` reports nothing to fix.
