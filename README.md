# SwiftMoLogger

Structured, multi-engine logging for Apple platforms — built on Swift Concurrency, instrumented for Instruments, and with a drop-in SwiftUI console.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/iOS%2015%20%7C%20macOS%2012%20%7C%20tvOS%2015%20%7C%20watchOS%208-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

*Created by Mohammed Elnaggar ([@MoElnaggar14](https://github.com/MoElnaggar14))*

---

## Why another logger?

Most Swift loggers do one thing well — pretty console output, or file rotation, or remote shipping — and force you to wire the rest yourself. SwiftMoLogger v3 is the opposite: **one call site, many destinations, zero ceremony**.

| Feature | SwiftMoLogger | Apple `os.Logger` | SwiftyBeaver | CocoaLumberjack |
|---|---|---|---|---|
| Structured `LogEntry` (level + tag + metadata + source location) | ✅ | ❌ (string only) | partial | partial |
| Multi-engine fan-out | ✅ | ❌ | ✅ | ✅ |
| Live `AsyncStream<LogEntry>` for SwiftUI / dashboards | ✅ | ❌ | ❌ | ❌ |
| Combine publisher | ✅ | ❌ | ❌ | ❌ |
| Drop-in SwiftUI log console | ✅ `SwiftMoLoggerUI` | ❌ | ❌ | ❌ |
| Built-in PII / secret redaction | ✅ `Redactor` | ❌ | ❌ | ❌ |
| Breadcrumbs for crash bundling | ✅ | ❌ | ❌ | ❌ |
| Auto `URLSession` request/response logging | ✅ `SwiftMoLoggerNetwork` | ❌ | ❌ | ❌ |
| Ready-made remote backends (Sentry/Datadog/Loki) | ✅ `SwiftMoLoggerRemote` | ❌ | partial | ❌ |
| Sampling + token-bucket rate limiting | ✅ | ❌ | ❌ | ❌ |
| App vitals (CPU/FPS/memory/thermal) | ✅ `SwiftMoLoggerDiagnostics` | ❌ | ❌ | ❌ |
| Live WebSocket tail to dev tools | ✅ | ❌ | ❌ | ❌ |
| Bug-report bundler (logs + breadcrumbs + device info) | ✅ | ❌ | ❌ | ❌ |
| XCTest assertion helpers | ✅ `SwiftMoLoggerTesting` | ❌ | ❌ | ❌ |
| `os_signpost` integration in one call | ✅ `LogSignpost.measure` | manual | ❌ | ❌ |
| MetricKit crash + hang capture | ✅ | ❌ | ❌ | ❌ |
| Ambient task-scoped context (`request_id`, `user_id`) | ✅ `@TaskLocal` | ❌ | ❌ | ❌ |
| App Store `PrivacyInfo.xcprivacy` manifest | ✅ | n/a | ❌ | ❌ |
| Sub-µs hot path (no engines) | ✅ ~140 ns | ~120 ns | ~3 µs | ~2 µs |

See [PERFORMANCE.md](PERFORMANCE.md) for measured numbers.

---

## Install

```swift
.package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "3.0.0")
```

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "SwiftMoLogger", package: "SwiftMoLogger"),
        .product(name: "SwiftMoLoggerUI", package: "SwiftMoLogger") // optional, SwiftUI console
    ]
)
```

---

## Quick start

```swift
import SwiftMoLogger

SwiftMoLogger.info("App started")
SwiftMoLogger.warn("Low memory")
SwiftMoLogger.error("Network failed")

// Tagged + structured
SwiftMoLogger.error("Payment declined", tag: .api, metadata: [
    "order_id": "ord_4291",
    "amount": 49.99,
    "retried": true
])
```

The default `SystemLogger` (Apple unified logging) is installed for you. **No configuration step is required.** Unlike the v2 release, info/warn entries are no longer silenced in release builds — only the `debug(_:)` helper is `#if DEBUG`.

---

## Adding engines

```swift
SwiftMoLogger.addEngine(MemoryLogEngine(capacity: 1_000))
SwiftMoLogger.addEngine(try FileLogEngine(
    fileURL: URL.documentsDirectory.appending(path: "app.log"),
    maxFileSizeBytes: 2 * 1_048_576,
    maxRotatedFiles: 3
))
```

All three built-in engines (`SystemLogger`, `MemoryLogEngine`, `FileLogEngine`) live in `Sources/` — not in scratch demo files. Custom engines need only conform to ``LogEngine``:

```swift
struct AnalyticsEngine: LogEngine {
    func log(_ entry: LogEntry) {
        guard entry.level >= .warning else { return }
        Analytics.track(entry.message, properties: entry.metadata.storage)
    }
}
SwiftMoLogger.addEngine(AnalyticsEngine())
```

---

## Swift Concurrency

### Ambient context

```swift
SwiftMoLogger.withContext(["request_id": "req-42", "user_id": "u-123"]) {
    SwiftMoLogger.info("Fetching profile")        // ← gets request_id + user_id
    try await api.fetchProfile()
    SwiftMoLogger.info("Profile cached")          // ← still gets them
}
SwiftMoLogger.info("Outside scope")               // ← clean
```

Works across `async` boundaries via the `withContext(_:_:) async` overload.

### Live stream

```swift
Task {
    for await entry in SwiftMoLogger.stream() where entry.level >= .error {
        await reportToBackend(entry)
    }
}
```

The stream is backed by `AsyncStream` — cancelling the `Task` automatically tears the subscription down.

### Sendable everywhere

`LogEntry`, `LogLevel`, `LogTag`, `LogMetadata`, and `SourceLocation` are all `Sendable`. Engines and the registry are safely callable from any actor.

---

## Performance instrumentation

```swift
let users = try LogSignpost.measure("loadUsers", tag: .database) {
    try userRepo.all()
}

// Async:
let response = try await LogSignpost.measureAsync("uploadAvatar") {
    try await uploader.send(image)
}
```

`measure` emits both an `os_signpost` interval (visible in Instruments' Points of Interest track) **and** a log entry with the elapsed ms in `metadata.elapsed_ms`. No more bracketing two `info` calls and computing a diff by hand.

---

## SwiftUI log console (`SwiftMoLoggerUI`)

```swift
import SwiftMoLoggerUI

struct DebugMenu: View {
    var body: some View {
        LogConsoleView()
    }
}
```

That's the entire integration. The console offers:

- live tailing with auto-scroll
- level filter (`trace` → `fault`)
- substring search across messages and tags
- pause / resume / clear
- per-row metadata + source location display

Backed by `LogConsoleViewModel`, an `@MainActor ObservableObject` you can also use headlessly.

---

## MetricKit crash + hang capture

```swift
let reporter = MetricKitCrashReporter()
reporter.crashReportDelegate = self
reporter.hangReportDelegate = self
reporter.startMonitoring()
```

Catches what in-process reporters miss: jetsam, watchdog timeouts, app-launch crashes, hangs > 250 ms. Logs are tagged `.crash` / `.performance`.

The module is gated to platforms where MetricKit is actually available (`iOS` + `macOS`); on tvOS / watchOS the file compiles to an empty translation unit so the package still builds.

---

## Engine catalogue

| Engine | Where | What it does |
|---|---|---|
| `SystemLogger` | `LogEngines/SystemLogger.swift` | Routes through `os.Logger`. Installed by default. |
| `MemoryLogEngine` | `LogEngines/MemoryLogEngine.swift` | Bounded ring buffer; O(1) append, filterable snapshot. |
| `FileLogEngine` | `LogEngines/FileLogEngine.swift` | JSON-Lines, async writes, size-based rotation. |
| `LogStream` | `Stream/LogStream.swift` | Fans entries out to one or more `AsyncStream` subscribers. |

---

## Production checklist — opt-in modules

| Module | When to add | Import |
|---|---|---|
| `SwiftMoLogger` | always | `import SwiftMoLogger` |
| `SwiftMoLoggerUI` | you want an in-app debug console | `import SwiftMoLoggerUI` |
| `SwiftMoLoggerNetwork` | you want auto `URLSession` request/response logging | `import SwiftMoLoggerNetwork` |
| `SwiftMoLoggerRemote` | you want Sentry / Datadog / Loki shipping | `import SwiftMoLoggerRemote` |
| `SwiftMoLoggerDiagnostics` | you want bug-report bundling, app vitals, or WebSocket tail | `import SwiftMoLoggerDiagnostics` |
| `SwiftMoLoggerTesting` | XCTest assertions over what was logged | `@testable import SwiftMoLoggerTesting` |

### PII / secret redaction

```swift
SwiftMoLogger.enableRedaction()    // wraps the default SystemLogger
// Or wrap a specific sink:
SwiftMoLogger.addEngine(RedactingLogEngine(wrapping: fileEngine))
```

The default `Redactor` strips emails, JWTs, Bearer tokens, AWS/GCP keys, credit cards, UUIDs, IPs, and phone numbers. Add custom rules via `Redactor.Rule` — full regex support.

### Breadcrumbs (auto-attached to crash reports)

```swift
SwiftMoLogger.breadcrumb("user tapped Buy", category: .userAction)
SwiftMoLogger.breadcrumb("nav → checkout", category: .navigation)

// On crash / bug report:
let crumbs: [Breadcrumb] = SwiftMoLogger.breadcrumbs()
```

Bounded ring buffer (default 100). O(1) append.

### Auto URLSession logging

```swift
import SwiftMoLoggerNetwork

let config = URLSessionConfiguration.default
NetworkLogger.install(on: config)
let session = URLSession(configuration: config)
// Every request is now logged with method/URL/status/duration_ms,
// sensitive headers are stripped, and breadcrumbs are recorded.
```

### Remote shipping

```swift
import SwiftMoLoggerRemote

SwiftMoLogger.addEngine(SentryLogEngine(
    dsn: URL(string: "https://abc@o123.ingest.sentry.io/456")!,
    release: "1.4.2",
    environment: "production"
))

SwiftMoLogger.addEngine(DatadogLogEngine(
    apiKey: "<DD_API_KEY>",
    site: .eu1,
    service: "checkout"
))

SwiftMoLogger.addEngine(LokiLogEngine(
    endpoint: URL(string: "https://loki.example.com/loki/api/v1/push")!,
    labels: ["job": "ios", "env": "prod"]
))
```

All shippers batch (50–100 entries), debounce (5 s), retry with exponential backoff, and never block the caller.

### Sampling + rate limiting

```swift
// Keep 1% of trace logs in production
SwiftMoLogger.addEngine(SamplingLogEngine(
    wrapping: fileEngine,
    strategy: .perLevel(rates: [.trace: 0.01, .debug: 0.1])
))

// Cap any sink at 50 logs/sec with a 100-burst
SwiftMoLogger.addEngine(RateLimitingLogEngine(
    wrapping: networkEngine,
    permitsPerSecond: 50,
    burst: 100
))
```

### Combine publisher

```swift
SwiftMoLogger.publisher()
    .filter { $0.level >= .error }
    .sink { entry in /* … */ }
    .store(in: &cancellables)
```

### XCTest assertions

```swift
import SwiftMoLoggerTesting

final class CheckoutTests: XCTestCase {
    var logs: RecordingLogEngine!
    override func setUp() { logs = SwiftMoLogger.installRecorder() }

    func testFailureIsLogged() {
        service.purchase(invalid: true)
        XCTAssertLogged(.error, contains: "declined", tag: .api, in: logs)
        XCTAssertLogCount(0, atLevel: .fault, in: logs)
    }
}
```

### App vitals (CPU / memory / FPS / thermal)

```swift
import SwiftMoLoggerDiagnostics
AppVitalsMonitor.shared.start(interval: 10)
```

Each tick emits a `.notice`-level log entry tagged `.performance` with `cpu_pct`, `memory_mb`, `fps`, `thermal`, and `battery` metadata.

### Bug-report bundler

```swift
let memory = MemoryLogEngine(capacity: 500)
SwiftMoLogger.addEngine(memory)

let report = try BugReporter(memoryEngine: memory, appName: "Acme")
    .generate(extras: ["screen": "checkout"])
// Returns a directory containing info.txt, breadcrumbs.json,
// logs.json, vitals.json — hand it to UIActivityViewController or a
// custom uploader.
```

### Live WebSocket tail (dev/QA only)

```swift
SwiftMoLogger.addEngine(WebSocketTailEngine(
    url: URL(string: "ws://192.168.1.42:9001")!
))

// On the receiving Mac:
//   wscat -l 9001
```

### Privacy manifest

`Sources/SwiftMoLogger/PrivacyInfo.xcprivacy` ships with the package and is included in the binary. It declares `NSPrivacyTracking = false` and lists the approved API reasons (file timestamps, bundle ID read, boot-time read). App Store submissions pass without further work.

---

## Tags

Tags live in namespaces for discoverability — and the flat shorthands still work for backwards compat:

```swift
SwiftMoLogger.info("hit", tag: .Network.api)        // namespaced
SwiftMoLogger.info("hit", tag: .api)                // shorthand, same tag
SwiftMoLogger.info("custom", tag: .custom("Feature", domain: "checkout"))
```

| Namespace | Members |
|---|---|
| `System` | `crash`, `performance`, `memory`, `lifecycle`, `internal` |
| `Network` | `network`, `api`, `download`, `upload`, `websocket` |
| `Data` | `database`, `cache`, `coredata`, `userdefaults`, `keychain`, `filesystem`, `parsing`, `serialization` |
| `UI` | `ui`, `navigation`, `animation`, `accessibility`, `layout` |
| `Security` | `authentication`, `authorization`, `biometrics`, `encryption`, `security` |
| `ThirdParty` | `firebase`, `analytics`, `crashlytics`, `notifications`, `sync`, `thirdparty` |
| `Business` | `business`, `validation`, `calculation`, `workflow` |
| `Development` | `debug`, `testing`, `mock`, `configuration` |
| `Media` | `image`, `video`, `audio`, `assets` |

---

## Development model

This project follows [GitFlow](GITFLOW.md). All feature PRs target `develop`; only release/hotfix PRs touch `main`. Branch policy is enforced by `.github/workflows/gitflow.yml`.

Active feature branches for v3:

- `feature/swift-concurrency`
- `feature/swiftui-console`
- `feature/performance-benchmarks`

---

## Migration from v2

| v2 | v3 | Notes |
|---|---|---|
| `LogEngine.info(message:)` | `LogEngine.log(_:)` | v2 methods still work via default implementations |
| `LogTag` is an enum | `LogTag` is a struct + namespaces | All `.api`, `.database` shorthands preserved |
| `SwiftMoLogger.getAllEngines()` | `SwiftMoLogger.allEngines()` | `getAllEngines()` kept as deprecated alias |
| info/warn dropped in release | always shipped | **Real bug fix** — v2 silently lost production logs |
| no metadata | `metadata: LogMetadata = [:]` on every call | |
| no source location | captured automatically via `#fileID` / `#line` | |
| no async stream | `SwiftMoLogger.stream()` | |
| no signposts | `LogSignpost.measure` | |
| no SwiftUI console | `import SwiftMoLoggerUI; LogConsoleView()` | |

---

## License

MIT. See [LICENSE](LICENSE).
