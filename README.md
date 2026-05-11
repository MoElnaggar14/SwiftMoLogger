# SwiftMoLogger

> **The logging package iOS teams wish they'd written.**
> Structured, multi-engine, Swift-Concurrency-native — with an in-app Instruments dashboard, zero-config live tail to your Mac, automatic PII redaction, Sentry/Datadog/Loki shippers, and Swift Macros. All in one package, all opt-in.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/iOS_15_•_macOS_12_•_tvOS_15_•_watchOS_8-lightgrey.svg)](https://developer.apple.com)
[![SPM](https://img.shields.io/badge/SPM-supported-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

*by Mohammed Elnaggar ([@MoElnaggar14](https://github.com/MoElnaggar14))*

---

## 30-second pitch

```swift
import SwiftMoLogger

// Day 1: it just works.
SwiftMoLogger.info("App started")
SwiftMoLogger.error("Payment failed", tag: .api, metadata: [
    "order_id": "ord_4291",
    "amount": 49.99
])
```

```swift
import SwiftMoLoggerUI

// Day 2: drop one view, get Instruments inside your app.
DiagnosticsHubView()
```

```bash
# Day 3: tail every device on your Wi-Fi from the terminal.
swift run swiftmologger-inspector
```

That's it. No `configure(…)`, no singletons to wire, no protocol gymnastics.

---

## Table of contents

- [Why SwiftMoLogger?](#why-swiftmologger)
- [Install](#install)
- [Architecture at a glance](#architecture-at-a-glance)
- [The headline features](#the-headline-features)
  - [1. Diagnostics Hub](#1-diagnostics-hub--instruments-inside-your-app)
  - [2. Bonjour live tail](#2-bonjour-live-tail--zero-config-mac-companion)
  - [3. Swift Macros](#3-swift-macros--zero-boilerplate-call-sites)
- [Core logging](#core-logging)
- [Production hardening](#production-hardening)
  - [PII redaction](#pii-redaction)
  - [Breadcrumbs](#breadcrumbs)
  - [Sampling + rate limiting](#sampling--rate-limiting)
  - [Remote shipping](#remote-shipping-sentry--datadog--loki)
  - [Auto network logging](#auto-network-logging)
  - [Privacy manifest](#privacy-manifest)
- [Swift Concurrency](#swift-concurrency)
- [Performance](#performance)
- [Testing](#testing)
- [Comparison](#comparison)
- [Migration from v2](#migration-from-v2)
- [Development model (GitFlow)](#development-model-gitflow)
- [License](#license)

---

## Why SwiftMoLogger?

| | What it solves |
|---|---|
| 🎯 | **Zero ceremony.** `SwiftMoLogger.info("hi")` works the moment you `import`. No configuration step. |
| 🧩 | **Structured everywhere.** Every call materialises a `LogEntry` with level + tag + metadata + source location + thread. No more parsing strings downstream. |
| 🚀 | **Sub-µs hot path.** ~140 ns when no engines are attached, ~310 ns with a memory engine. See [PERFORMANCE.md](PERFORMANCE.md). |
| 🛡 | **Production-safe by default.** Built-in PII / token / credit-card redaction. Rate limiting. Sampling. Privacy manifest. |
| 🔭 | **Self-hosted observability.** `DiagnosticsHubView()` is Instruments + Charles + Console inside your app. No cable, no Mac required. |
| 📡 | **Zero-config live tail.** Bonjour-advertised devices, terminal CLI on your Mac auto-discovers them all. |
| 🧪 | **First-class testing.** Drop-in XCTest assertions over what was logged. |
| 🪶 | **Opt-in everything.** 7 separate library products. Pay only for what you import. |

---

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "3.0.0")
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "SwiftMoLogger", package: "SwiftMoLogger"),
        // …add only what you need:
        .product(name: "SwiftMoLoggerUI", package: "SwiftMoLogger"),
        .product(name: "SwiftMoLoggerNetwork", package: "SwiftMoLogger"),
        .product(name: "SwiftMoLoggerRemote", package: "SwiftMoLogger"),
        .product(name: "SwiftMoLoggerDiagnostics", package: "SwiftMoLogger"),
        .product(name: "SwiftMoLoggerTesting", package: "SwiftMoLogger"),
        .product(name: "SwiftMoLoggerSugar", package: "SwiftMoLogger"),
    ])
]
```

---

## Architecture at a glance

```
┌─────────────────────────────────────────────────────────────┐
│                     YOUR APP                                │
│       SwiftMoLogger.info("...", tag: .api, metadata: ...)   │
└──────────────────────────────┬──────────────────────────────┘
                               │
                ┌──────────────▼──────────────┐
                │      EngineRegistry         │  os_unfair_lock
                │   (level filter + fan-out)  │  ~140 ns hot path
                └──────┬─────┬─────┬─────┬────┘
       ┌──────────────┘     │     │     └──────────────┐
       │                    │     │                    │
   ┌───▼───┐         ┌─────▼─┐ ┌─▼──────┐         ┌────▼────┐
   │System │         │Memory │ │ File   │   …     │ Custom  │
   │Logger │         │Engine │ │Engine  │         │ Engine  │
   └───────┘         └───────┘ └────────┘         └─────────┘
       │                    │     │                    │
   os.Logger              ring   JSONL              Sentry /
                          buffer rotation           Datadog /
                                                    Loki / WS / …
```

Decorators (`Redacting`, `Sampling`, `RateLimiting`) wrap any engine. Streams (`AsyncStream<LogEntry>`, Combine `Publisher`) tap the registry. The SwiftUI Hub reads from shared `NetworkEventStore` / `SignpostEventStore` / `VitalsHistoryStore` / `BreadcrumbStore`.

### Products

| Product | What you get |
|---|---|
| **`SwiftMoLogger`** | Core: levels, tags, metadata, engines, registry, MetricKit, breadcrumbs, redaction, sampling, rate-limiting, Combine, signposts |
| **`SwiftMoLoggerUI`** | SwiftUI console (`LogConsoleView`) + **`DiagnosticsHubView`** (the headline) |
| **`SwiftMoLoggerNetwork`** | `URLProtocol` that auto-logs every `URLSession` request |
| **`SwiftMoLoggerRemote`** | `HTTPLogShipper` + ready-made `SentryLogEngine` / `DatadogLogEngine` / `LokiLogEngine` |
| **`SwiftMoLoggerDiagnostics`** | `LiveSink` (Bonjour), `AppVitalsMonitor`, `BugReporter`, `WebSocketTailEngine` |
| **`SwiftMoLoggerTesting`** | `XCTAssertLogged` + `RecordingLogEngine` |
| **`SwiftMoLoggerSugar`** | `#log` / `#measure` / `@AutoLog` Swift Macros |
| **`swiftmologger-inspector`** | Mac CLI executable for live tail |

---

## The headline features

### 1. Diagnostics Hub — Instruments inside your app

One SwiftUI view that turns any build into a self-hosted observability cockpit. **No cable, no Mac, no Xcode — just open the app.**

```swift
import SwiftMoLoggerUI

struct DebugTab: View {
    var body: some View { DiagnosticsHubView() }
}
```

```
┌──────────────────────────────────────────────────────────────────┐
│ 🔍 Diagnostics Hub      📄 421   🌐 38   〰 12   [🗑 clear]       │
├──────────────────────────────────────────────────────────────────┤
│ 14:22:01 ┃▌▌▌▎▎▍▏ █▌▌▎▎▍▏▏  ▎▌█▌▌▎▍▏  ▌▎▍▎▍▏ ┃ 14:23:01          │
│           ━━━━━━━━━━━━━━━━━━━━●━━━━━━━━                          │
├──────────────────────────────────────────────────────────────────┤
│  [📄 Logs] [🌐 Network] [〰 Signposts] [💗 Vitals] [🐚 Crumbs]   │
├──────────────────────────────────────────────────────────────────┤
│ ▶ GET /v1/users      ████░░░░░░  142ms  [200]                    │
│ ▶ POST /v1/checkout  ████████░░  423ms  [201]                    │
│ ▶ GET /v1/products   ███████████ 891ms  [500]                    │
└──────────────────────────────────────────────────────────────────┘
```

You get:

- **Timeline scrubber** with log-density bar — rewind up to 10 minutes
- **Network waterfall** of every URLSession request (colour-coded by status)
- **Signpost flame graph** with automatic lane assignment
- **Vitals charts** (memory / CPU / FPS / thermal) via Swift Charts
- **Breadcrumb trail** with category-coloured pins

### 2. Bonjour live tail — zero-config Mac companion

The on-device `LiveSink` advertises a Bonjour service. The bundled Mac CLI discovers every device on the network and pretty-prints every log line.

```swift
#if DEBUG
import SwiftMoLoggerDiagnostics
let sink = LiveSink()
try sink.start()
SwiftMoLogger.addEngine(sink)
#endif
```

```bash
$ swift run swiftmologger-inspector
SwiftMoLogger Inspector — discovering _swiftmologger._tcp on local network…
◉ discovered MyApp-iPhone-15
◉ discovered MyApp-iPad-Pro
● connected MyApp-iPhone-15
● connected MyApp-iPad-Pro

14:22:01.124 INFO  MyApp-iPhone-15 [API]      HTTP response status=200 duration_ms=132
14:22:01.221 WARN  MyApp-iPad-Pro  [Layout]   Auto-layout broke 3 constraints
14:22:01.337 ERROR MyApp-iPhone-15 [Database] Migration v4 → v5 timed out
```

Multiple devices, one terminal, no Xcode needed.

### 3. Swift Macros — zero-boilerplate call sites

```swift
import SwiftMoLoggerSugar

#log("user signed in", level: .info, tag: .api)
// Captures #fileID / #function / #line at the call site.

let users = #measure("loadUsers") {
    try repo.all()
}
// Lowers to LogSignpost.measure("loadUsers") { … }

@AutoLog
final class CheckoutService {
    func purchase(_ id: String) throws { … }
}
```

Macros live in a separate `SwiftMoLoggerSugar` product so the `swift-syntax` build cost is opt-in.

---

## Core logging

```swift
import SwiftMoLogger

// 8 levels mapped to OSLogType
SwiftMoLogger.trace("internals")
SwiftMoLogger.debug("only in DEBUG builds")
SwiftMoLogger.info("happy path")
SwiftMoLogger.notice("worth noticing")
SwiftMoLogger.warn("looks off")
SwiftMoLogger.error("broke")
SwiftMoLogger.critical("badly broke")
SwiftMoLogger.fault("unrecoverable")

// Errors with auto-metadata
SwiftMoLogger.error(error, tag: .api)
// → metadata.error_type, metadata.error captured automatically

// Tagged with namespaces — code completion friendly
SwiftMoLogger.info("hit cache", tag: .Data.cache)
SwiftMoLogger.warn("slow query", tag: .Data.database)
SwiftMoLogger.info("custom", tag: .custom("Checkout", domain: "checkout"))

// Global level filter — short-circuits before any allocation
SwiftMoLogger.minimumLevel = .info  // drops trace + debug everywhere
```

### Engines

```swift
SwiftMoLogger.addEngine(MemoryLogEngine(capacity: 1_000))
SwiftMoLogger.addEngine(try FileLogEngine(
    fileURL: URL.documentsDirectory.appending(path: "app.log"),
    maxFileSizeBytes: 2 * 1_048_576,
    maxRotatedFiles: 3
))
```

Write your own in 3 lines:

```swift
struct AnalyticsEngine: LogEngine {
    func log(_ entry: LogEntry) {
        guard entry.level >= .warning else { return }
        Analytics.track(entry.message, properties: entry.metadata.storage)
    }
}
SwiftMoLogger.addEngine(AnalyticsEngine())
```

### LogTagged — automatic per-object tagging

```swift
struct APIService: LogTagged {
    var logTag: LogTag { .api }
}

let service = APIService()
service.logInfo("hit")           // → automatically tagged [API]
service.logError(networkError)   // → tag + structured error metadata
```

---

## Production hardening

### PII redaction

Every log line passes through a regex-based scrubber **before** it leaves your process.

```swift
SwiftMoLogger.enableRedaction()  // one-line install over SystemLogger
```

Default rules: JWT, Bearer / Basic tokens, AWS / GCP keys, emails, credit cards, phone numbers, IPv4, UUIDs. Walks `metadata` recursively. Custom rules:

```swift
var redactor = Redactor()
try redactor.add(Redactor.Rule(name: "ssn", pattern: #"\d{3}-\d{2}-\d{4}"#))
SwiftMoLogger.addEngine(RedactingLogEngine(wrapping: networkEngine, redactor: redactor))
```

### Breadcrumbs

```swift
SwiftMoLogger.breadcrumb("user tapped Buy", category: .userAction)
SwiftMoLogger.breadcrumb("nav → checkout", category: .navigation)

// Attach to a crash report / bug report
let crumbs: [Breadcrumb] = SwiftMoLogger.breadcrumbs()
```

Bounded ring buffer (default 100), O(1) append, `Sendable` value type matching the Sentry / Bugsnag shape so shipping is a 1:1 mapping.

### Sampling + rate limiting

```swift
// Keep 1% of trace logs in production
SwiftMoLogger.addEngine(SamplingLogEngine(
    wrapping: fileEngine,
    strategy: .perLevel(rates: [.trace: 0.01, .debug: 0.1])
))

// Cap any sink at 50 logs/sec with a 100-event burst
SwiftMoLogger.addEngine(RateLimitingLogEngine(
    wrapping: networkEngine,
    permitsPerSecond: 50,
    burst: 100
))
```

Token-bucket rate limiter, thread-local PRNG for sampling — both ~ns-class overhead.

### Remote shipping (Sentry / Datadog / Loki)

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

All shippers: batch (50–100), debounce (5 s), retry with exponential backoff, cap buffered entries on long offline spells. `log()` is O(1) — network happens off the caller's thread.

### Auto network logging

```swift
import SwiftMoLoggerNetwork

let config = URLSessionConfiguration.default
NetworkLogger.install(on: config)
let session = URLSession(configuration: config)
// Every request is now logged with method/URL/status/duration_ms
// + breadcrumbs are recorded. Sensitive headers stripped automatically.
```

`Authorization`, `Cookie`, `X-API-Key`, `X-Auth-Token` and friends are stripped by default — extend `NetworkLoggingProtocol.sensitiveHeaders` to add more.

### Privacy manifest

`PrivacyInfo.xcprivacy` ships in the package. It declares:

- `NSPrivacyTracking = false` (no tracking)
- No collected data types
- Approved API reasons: UserDefaults (CA92.1), FileTimestamp (C617.1), SystemBootTime (35F9.1)

App Store submissions pass without further work.

---

## Swift Concurrency

### Task-local ambient context

```swift
SwiftMoLogger.withContext(["request_id": "req-42", "user_id": "u-123"]) {
    SwiftMoLogger.info("fetching profile")   // ← inherits both keys
    try await api.fetchProfile()
    SwiftMoLogger.info("profile cached")     // ← still inherits
}
SwiftMoLogger.info("outside scope")          // ← clean
```

Backed by `@TaskLocal` — concurrent `Task`s see their own scope without interfering.

### AsyncStream of entries

```swift
Task {
    for await entry in SwiftMoLogger.stream() where entry.level >= .error {
        await reportToBackend(entry)
    }
}
```

### Combine publisher (alternative)

```swift
SwiftMoLogger.publisher()
    .filter { $0.level >= .error }
    .sink { entry in /* … */ }
    .store(in: &cancellables)
```

### Signposts for Instruments

```swift
let users = try LogSignpost.measure("loadUsers", tag: .database) {
    try userRepo.all()
}

let response = try await LogSignpost.measureAsync("uploadAvatar") {
    try await uploader.send(image)
}
```

One call emits both an `os_signpost` interval (visible in Instruments' Points of Interest) **and** a log entry with `metadata.elapsed_ms`.

---

## Performance

Measured on M1 MacBook Pro, iOS 17 simulator, release build:

| Scenario | per-call median |
|---|---|
| `info("…")` — no engines | **~140 ns** |
| `info("…")` — `MemoryLogEngine` only | **~310 ns** |
| `info("…")` filtered out by `minimumLevel` | **~35 ns** |
| `info("…")` — `SystemLogger` (os.log) | **~820 ns** |
| Concurrent 8 threads × 2 000 calls | linear scaling, ~22 ms total |

Memory: `LogEntry` is 200 B on the stack with zero heap unless `metadata` is non-empty. `MemoryLogEngine` pre-allocates its ring buffer — zero growth, zero GC churn.

Full benchmarks + design rationale → [PERFORMANCE.md](PERFORMANCE.md).

---

## Testing

```swift
import SwiftMoLoggerTesting

final class CheckoutTests: XCTestCase {
    var logs: RecordingLogEngine!

    override func setUp() {
        logs = SwiftMoLogger.installRecorder()
    }

    func testFailureIsLogged() async throws {
        try await service.purchase(invalid: true)
        XCTAssertLogged(.error, contains: "declined", tag: .api, in: logs)
        XCTAssertLogCount(0, atLevel: .fault, in: logs)
    }
}
```

`RecordingLogEngine` captures everything; assertions are simple, scoped to a single test, and zero-config.

---

## Comparison

| | SwiftMoLogger | os.Logger | SwiftyBeaver | CocoaLumberjack |
|---|:-:|:-:|:-:|:-:|
| Structured `LogEntry` | ✅ | ❌ (string) | ⚠️ | ⚠️ |
| Multi-engine fan-out | ✅ | ❌ | ✅ | ✅ |
| `AsyncStream<LogEntry>` | ✅ | ❌ | ❌ | ❌ |
| Combine publisher | ✅ | ❌ | ❌ | ❌ |
| **In-app Instruments view** | ✅ | ❌ | ❌ | ❌ |
| **Bonjour live tail** | ✅ | ❌ | ❌ | ❌ |
| Built-in PII redaction | ✅ | ❌ | ❌ | ❌ |
| Breadcrumbs | ✅ | ❌ | ❌ | ❌ |
| Auto `URLSession` capture | ✅ | ❌ | ❌ | ❌ |
| Sentry / Datadog / Loki | ✅ | ❌ | ⚠️ | ❌ |
| Sampling + rate limit | ✅ | ❌ | ❌ | ❌ |
| App vitals (CPU/FPS/mem) | ✅ | ❌ | ❌ | ❌ |
| Swift Macros | ✅ | ❌ | ❌ | ❌ |
| `XCTAssertLogged` | ✅ | ❌ | ❌ | ❌ |
| Privacy manifest | ✅ | n/a | ❌ | ❌ |
| Task-local context | ✅ | ❌ | ❌ | ❌ |
| Hot path (no engines) | **~140 ns** | ~120 ns | ~3 µs | ~2 µs |

---

## Migration from v2

| v2 | v3 | Notes |
|---|---|---|
| `LogEngine.info(message:)` | `LogEngine.log(_:)` | v2 methods kept as default-impls |
| `LogTag` is `enum` | `LogTag` is `struct` + namespaces | All `.api` shorthands preserved |
| `getAllEngines()` | `allEngines()` | Old name kept as deprecated alias |
| info/warn silently dropped in release | always shipped | **Real bug fix** |
| no metadata | `metadata: [:]` on every call | |
| no source location | captured via `#fileID` / `#line` | automatic |
| no AsyncStream | `SwiftMoLogger.stream()` | |
| no signpost integration | `LogSignpost.measure` | |
| no SwiftUI console | `LogConsoleView`, `DiagnosticsHubView` | |

---

## Development model (GitFlow)

| Branch | Purpose | Direct push? |
|---|---|---|
| `main` | tagged releases only | ❌ release PR |
| `develop` | integration | ❌ via PR |
| `feature/*` | new features → develop | merge to develop |
| `bugfix/*` | bug fixes → develop | merge to develop |
| `release/*` | release prep → main + develop | merge both |
| `hotfix/*` | emergency from main | merge both |

Branch policy is enforced by `.github/workflows/gitflow.yml`. Full procedure → [GITFLOW.md](GITFLOW.md).

---

## License

MIT. See [LICENSE](LICENSE).

---

<p align="center">
<sub>Built with care by <a href="https://github.com/MoElnaggar14">@MoElnaggar14</a>. If it helped you ship faster, drop a ⭐.</sub>
</p>
