# SwiftMoLogger

> **The logging package iOS teams wish they'd written.**
> Structured, multi-engine, Swift-Concurrency-native — with an in-app Instruments dashboard, zero-config live tail to your Mac, opt-in PII redaction, Sentry/Datadog/Loki shippers, and Swift Macros. All in one package, all opt-in.

[![Swift](https://img.shields.io/badge/Swift-6.1_→_6.4_tested-orange.svg)](https://swift.org)
[![Platforms](https://img.shields.io/badge/iOS_16_•_macOS_13_•_tvOS_16_•_watchOS_9_•_visionOS_1-lightgrey.svg)](https://developer.apple.com)
[![SPM](https://img.shields.io/badge/SPM-supported-brightgreen.svg)](https://swift.org/package-manager/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

*by Mohammed Elnaggar ([@MoElnaggar14](https://github.com/MoElnaggar14))*

---

## 30-second pitch

```swift
import SwiftMoLogger

// Day 1: build one environment at your composition root, inject the logger.
@main
struct ShopApp: App {
    private let logging = LogEnvironment()

    init() {
        logging.registry.addEngine(MemoryLogEngine(capacity: 1_000))
    }

    var body: some Scene {
        WindowGroup {
            RootView(checkout: CheckoutService(log: logging.logger))
        }
    }
}

final class CheckoutService {
    private let log: MoLogger
    init(log: MoLogger) { self.log = log.with(tag: .api) }

    func paymentFailed(orderID: String) {
        log.error("Payment failed", metadata: [
            "order_id": .string(orderID),
            "amount": 49.99
        ])
    }
}
```

```swift
import SwiftMoLoggerUI

// Day 2: drop one view, get Instruments inside your app.
DiagnosticsHubView(environment: logging)
```

```bash
# Day 3: tail every device on your Wi-Fi from the terminal.
swift run swiftmologger-inspector
```

Want to see it first? Open [`ExampleApp/SwiftMoLoggerExample.xcodeproj`](ExampleApp) and run it on a simulator or your iPhone.

That's it. No `configure(…)` step, no protocol gymnastics, and no singletons: one `LogEnvironment` you inject.

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
  - [Per-tag levels and remote config](#per-tag-levels-and-remote-config)
  - [Sampling + rate limiting](#sampling--rate-limiting)
  - [Remote shipping](#remote-shipping-sentry--datadog--loki--opentelemetry)
  - [Crash reporters and analytics](#crash-reporters-and-analytics)
  - [Auto network logging](#auto-network-logging)
  - [Privacy manifest](#privacy-manifest)
- [Distributed tracing](#distributed-tracing-w3c)
- [Flight recorder](#flight-recorder--black-box-for-crashes)
- [Error grouping](#error-grouping)
- [Swift Concurrency](#swift-concurrency)
- [Performance](#performance)
- [Testing](#testing)
- [Comparison](#comparison)
- [Upgrading](#upgrading)
- [Use with AI coding agents](#use-with-ai-coding-agents)
- [Development model (GitFlow)](#development-model-gitflow)
- [📚 Article series](#-article-series)
- [Xcode code snippets](#xcode-code-snippets)
- [License](#license)

---

## Why SwiftMoLogger?

| | What it solves |
|---|---|
| 🎯 | **No singletons, no ceremony.** Create one `LogEnvironment()` at app start and inject `environment.logger`. No configuration step, no hidden global state, and every dependency is visible in your initialisers. |
| 🧩 | **Structured everywhere.** Every call materialises a `LogEntry` with level + tag + metadata + source location + thread. No more parsing strings downstream. |
| 🚀 | **Sub-µs hot path.** ~140 ns when no engines are attached, ~310 ns with a memory engine. See [PERFORMANCE.md](PERFORMANCE.md). |
| 🛡 | **Production hardening built in.** Opt-in PII / token / credit-card redaction. Rate limiting. Sampling. Privacy manifests. |
| 🔭 | **Self-hosted observability.** `DiagnosticsHubView(environment:)` is Instruments + Charles + Console inside your app. No cable, no Mac required. |
| 📡 | **Zero-config live tail.** Bonjour-advertised devices, terminal CLI on your Mac auto-discovers them all. |
| 🛰 | **W3C distributed tracing.** Stamp outbound `URLSession` requests with `traceparent` so iOS spans show up next to your backend trace. |
| 📼 | **Flight recorder.** Rolling 2-minute black box persisted to disk; replay the seconds before a crash on next launch. |
| 🪞 | **Smart error grouping.** Spammy retries collapse into one card with a count, not 1 000 noise lines. |
| 🧪 | **First-class testing.** Inject a recording logger, assert on what was logged. Each test owns its environment, so suites run isolated and in parallel. |
| 🪶 | **Opt-in everything.** 8 separate library products. Pay only for what you import. |

---

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "4.1.0")
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
        .product(name: "SwiftMoLoggerSwiftLog", package: "SwiftMoLogger"),
    ])
]
```

**Requirements:** Xcode 16+ (swift-tools-version 6.0). iOS 16, macOS 13, tvOS 16, watchOS 9, visionOS 1. CI tests with Swift 6.4 (Xcode 27), 6.3 (Xcode 26.6) and 6.1 (Xcode 16.4), builds for every platform, and builds the macros against swift-syntax 509 through 604.

---

## Architecture at a glance

```
┌─────────────────────────────────────────────────────────────┐
│              YOUR APP  (MoLogger injected)                  │
│        logger.info("...", tag: .api, metadata: ...)         │
└──────────────────────────────┬──────────────────────────────┘
                               │
                ┌──────────────▼──────────────┐
                │ EngineRegistry (per env)    │  os_unfair_lock
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

Everything hangs off one `LogEnvironment` that you create at your composition root: its `registry`, a `logger` (`MoLogger`) bound to it, a live `stream`, a `signposter`, and the diagnostics stores (`breadcrumbs`, `networkEvents`, `signposts`, `vitals`). Inject the narrowest piece a component needs. Decorators (`Redacting`, `Sampling`, `RateLimiting`) wrap any engine. Streams (`AsyncStream<LogEntry>`, Combine `Publisher`) tap the registry. The SwiftUI Hub reads from the environment's `NetworkEventStore` / `SignpostEventStore` / `VitalsHistoryStore` / `BreadcrumbStore`.

### Products

| Product | What you get |
|---|---|
| **`SwiftMoLogger`** | Core: `LogEnvironment`, `MoLogger`, levels, tags, metadata, engines, registry, MetricKit, breadcrumbs, redaction, sampling, rate-limiting, Combine, signposts |
| **`SwiftMoLoggerUI`** | SwiftUI console (`LogConsoleView`) + **`DiagnosticsHubView`** (the headline) |
| **`SwiftMoLoggerNetwork`** | `NetworkLogger`, a `URLSessionTaskDelegate` you inject to log `URLSession` traffic |
| **`SwiftMoLoggerRemote`** | `HTTPLogShipper` + ready-made `SentryLogEngine` / `DatadogLogEngine` / `LokiLogEngine` / `OTLPLogEngine` |
| **`SwiftMoLoggerDiagnostics`** | `LiveSink` (Bonjour), `AppVitalsMonitor`, `BugReporter`, `WebSocketTailEngine` |
| **`SwiftMoLoggerTesting`** | `XCTAssertLogged` + `RecordingLogEngine` |
| **`SwiftMoLoggerSugar`** | `#log` / `#measure` / `@AutoLog` Swift Macros |
| **`SwiftMoLoggerSwiftLog`** | `SwiftMoLogHandler`, a swift-log backend that routes into your engines |
| **`swiftmologger-inspector`** | Mac CLI executable for live tail |

---

## The headline features

### 1. Diagnostics Hub — Instruments inside your app

One SwiftUI view that turns any build into a self-hosted observability cockpit. **No cable, no Mac, no Xcode — just open the app.**

```swift
import SwiftMoLoggerUI

struct DebugTab: View {
    let logging: LogEnvironment   // injected from your App
    var body: some View { DiagnosticsHubView(environment: logging) }
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
- **Network waterfall** of every request logged by a [`NetworkLogger`](#auto-network-logging) (colour-coded by status)
- **Signpost flame graph** with automatic lane assignment
- **Vitals charts** (memory / CPU / FPS / thermal) via Swift Charts
- **Breadcrumb trail** with category-coloured pins

The Hub reads the environment's stores, so feed them from the same `LogEnvironment`. For the vitals charts, run an `AppVitalsMonitor` with the environment's history store:

```swift
import SwiftMoLoggerDiagnostics

let vitals = AppVitalsMonitor(logger: logging.logger, history: logging.vitals)
vitals.start(interval: 5)
```

Just want a log console? `LogConsoleView(stream: logging.stream)`.

### 2. Bonjour live tail — zero-config Mac companion

The on-device `LiveSink` advertises a Bonjour service. The bundled Mac CLI discovers every device on the network and pretty-prints every log line.

```swift
#if DEBUG
import SwiftMoLoggerDiagnostics
let sink = LiveSink(statusLogger: logging.logger)
try sink.start()
logging.registry.addEngine(sink)
#endif
```

On iOS, advertising on the local network needs two Info.plist keys, or the listener fails on a real device:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Streams debug logs to the SwiftMoLogger Inspector on your Mac.</string>
<key>NSBonjourServices</key>
<array>
    <string>_swiftmologger._tcp</string>
</array>
```

`LiveSink` streams unencrypted, unauthenticated log lines to anyone on the network, so keep it behind `#if DEBUG` (or a debug-only build configuration) and add the keys to that configuration's Info.plist only.

```bash
$ swift run swiftmologger-inspector
SwiftMoLogger Inspector — discovering _swiftmologger._tcp on local network…
◉ discovered MyApp-iPhone-15
◉ discovered MyApp-iPad-Pro
● connected MyApp-iPhone-15
2026-10-05T14:22:01.124Z INFO  MyApp-iPhone-15 [API] [thread] HTTP response 200
2026-10-05T14:22:01.221Z WARN  MyApp-iPad-Pro [Layout] [main] Auto-layout broke 3 constraints
2026-10-05T14:22:01.337Z ERROR MyApp-iPhone-15 [Database] [thread] Migration v4 → v5 timed out
```

Each line shows timestamp (UTC), level, device, tag, thread and message. Metadata isn't printed, so keep the key fact in the message. Multiple devices, one terminal, no Xcode needed.

**Ask your AI agent.** [`swiftmologger-mcp`](Tools/swiftmologger-mcp) is an MCP server that gives Claude Code, Codex or Cursor the same live tail, with tools to search, read an entry in context, list failed HTTP requests and wait for the next error while you reproduce a bug. Entries are redacted before the agent sees them.

### 3. Swift Macros — zero-boilerplate call sites

```swift
import SwiftMoLoggerSugar

#log(logger, "user signed in", level: .info, tag: .api)
// Captures #fileID / #function / #line at the call site.

let users = try #measure(signposter, "loadUsers") {
    try repo.all()
}
// Lowers to signposter.measure("loadUsers") { … }

@AutoLog
final class CheckoutService {
    let logger: MoLogger                 // @AutoLog logs through this injected property
    init(logger: MoLogger) { self.logger = logger }

    func purchase(_ id: String) throws {
        __autoLog()                      // synthesised helper: trace entry "→ purchase(_:)"
        …
    }
}
```

Every macro takes its logger or signposter explicitly (or, for `@AutoLog`, from a `logger: MoLogger` property), so nothing global is involved. Macros live in a separate `SwiftMoLoggerSugar` product so the `swift-syntax` build cost is opt-in.

---

## Core logging

```swift
import SwiftMoLogger

let logging = LogEnvironment()   // once, at your composition root
let logger = logging.logger      // inject this (or a child) wherever you log

// 8 levels mapped to OSLogType
logger.trace("internals")
logger.debug("only in DEBUG builds")
logger.info("happy path")
logger.notice("worth noticing")
logger.warning("looks off")
logger.error("broke")
logger.critical("badly broke")
logger.fault("unrecoverable")

// Errors with auto-metadata
logger.error(error, tag: .api)
// → metadata.error_type, metadata.error captured automatically

// Tagged with namespaces — code completion friendly
logger.info("hit cache", tag: .Data.cache)
logger.warning("slow query", tag: .Data.database)
logger.info("custom", tag: .custom("Checkout", domain: "checkout"))

// Registry-wide level filter — short-circuits before any allocation
logging.registry.minimumLevel = .info  // drops trace + debug for every logger on this registry
logging.registry.setMinimumLevel(.trace, for: .Data.database)  // except one area; see Per-tag levels
```

### Engines

Engines are configured on the environment's registry:

```swift
logging.registry.addEngine(MemoryLogEngine(capacity: 1_000))
logging.registry.addEngine(try FileLogEngine(
    fileURL: URL.documentsDirectory.appending(path: "app.log"),
    maxFileSizeBytes: 2 * 1_048_576,
    maxRotatedFiles: 3,
    protection: .completeUnlessOpen   // unreadable while locked, still writable in the background
))
```

Log files can hold personal data even with redaction on, so `FileLogEngine` sets a data-protection class on every file it creates, rotated ones included. The default, `.completeUntilFirstUserAuthentication`, matches iOS's own default and states it explicitly, so an app-wide `.complete` entitlement can't silently break background logging. `.completeUnlessOpen` is the strongest class that keeps logging (and rotation) working while the device is locked. Avoid `.complete` unless the app never logs in the background. macOS has no per-file protection, so the option does nothing there.

Write your own in 3 lines:

```swift
final class AnalyticsEngine: LogEngine {
    func log(_ entry: LogEntry) {
        guard entry.level >= .warning else { return }
        Analytics.track(entry.message, properties: entry.metadata.storage)
    }
}
logging.registry.addEngine(AnalyticsEngine())
```

Or skip the class: `ForwardingLogEngine(minimumLevel: .warning) { entry in … }` does the same with a closure. See [Crash reporters and analytics](#crash-reporters-and-analytics).

### Flushing

Engines that buffer (`FileLogEngine`, the remote shippers) write or send what they hold when you call `registry.flush()`. iOS can terminate a suspended app without warning, so flush when the app moves to the background:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .background { logging.registry.flush() }
}
```

Custom engines get a do-nothing `flush()` by default; override it if your engine buffers. The redaction, sampling, rate-limiting and grouping decorators forward it to the engine they wrap. The flight recorder flushes itself.

### Child loggers — per-component tagging

```swift
let api = logger.with(tag: .api)
api.info("hit")                   // → automatically tagged [API]
api.error(networkError)           // → tag + structured error metadata

let checkout = api.with(metadata: ["component": "checkout"])
checkout.info("Paying")           // → [API] + component=checkout
```

### Injecting a logger

There is no static API and no shared instance: components *receive* their
logger through their initialiser. `MoLogger` is a small `Sendable` value
holding a registry, a default tag and bound metadata, so it's cheap to pass
around and to specialise:

```swift
final class CheckoutService {
    private let log: MoLogger

    init(log: MoLogger) {
        self.log = log.with(tag: .business).with(metadata: ["component": "checkout"])
    }

    func pay(orderID: String) {
        log.info("Paying", metadata: ["order_id": .string(orderID)])
    }
}

let checkout = CheckoutService(log: logging.logger)
```

Prefer the narrowest dependency: a service needs a `MoLogger`, a view model
that leaves breadcrumbs needs a `BreadcrumbStore`, a screen that measures
work needs a `Signposter`. Only the composition root (and things like the
Diagnostics Hub) need the whole `LogEnvironment`. Because each logger points
at the registry it was given, a framework can keep its logs separate from the
host app's with its own `LogEnvironment`, or log into the host's by accepting
a `MoLogger`.

### swift-log interop

SwiftNIO, AsyncHTTPClient, gRPC, the AWS SDK and much of the server/SPM
ecosystem log through [swift-log](https://github.com/apple/swift-log). Route
all of it into your engines with one line at your composition root:

```swift
import SwiftMoLoggerSwiftLog

SwiftMoLogHandler.bootstrap(logger: logging.logger)   // once per process (swift-log's own hook)
Logger(label: "com.example.sync").info("Synced", metadata: ["items": "42"])
```

Entries are tagged with the logger's label (domain `swiftlog.<label>`), and
swift-log metadata keeps its structure. Metadata providers are supported.

---

## Production hardening

### Keep PII out of sysdiagnose

The unified log ends up in sysdiagnose archives that users send to support.
By default the system logger uses `.privateInRelease`: messages are readable while you
debug and show as `<private>` in release builds. Choose another level if you need to:

```swift
// Same subsystem/category as the default system logger, so this replaces it in place.
logging.registry.addEngine(SystemLogger(privacy: .public))   // readable everywhere
```

`.hashed` redacts while keeping a stable hash, so identical messages can still be correlated.

### PII redaction

Redaction is opt-in. Turn it on and log lines pass through a regex-based scrubber **before** they reach the system log.

```swift
logging.registry.enableRedaction(at: 0)  // wraps the default SystemLogger in place
```

Wrap every other engine that persists or ships logs (`FileLogEngine`, remote shippers, `LiveSink`) in a `RedactingLogEngine` as well; `enableRedaction(at:)` only covers the engine at that index.

Default rules: JWT, Bearer / Basic tokens, AWS / GCP keys, emails, credit cards, phone numbers, IPv4, UUIDs. Walks `metadata` recursively. Custom rules:

```swift
var redactor = Redactor()
try redactor.add(Redactor.Rule(name: "ssn", pattern: #"\d{3}-\d{2}-\d{4}"#))
logging.registry.addEngine(RedactingLogEngine(wrapping: networkEngine, redactor: redactor))
```

Register the wrapper *instead of* the engine. If the engine is already registered, swap it in place, or the raw copy keeps logging unredacted:

```swift
logging.registry.replaceEngine(id: networkEngine.engineID) { RedactingLogEngine(wrapping: $0, redactor: redactor) }
```

### Breadcrumbs

```swift
let breadcrumbs = logging.breadcrumbs   // a BreadcrumbStore; inject it where you need it

breadcrumbs.record("user tapped Buy", category: .userAction)
breadcrumbs.record("nav → checkout", category: .navigation)

// Attach to a crash report / bug report
let crumbs: [Breadcrumb] = breadcrumbs.snapshot()
```

Bounded ring buffer (default 100), O(1) append, `Sendable` value type matching the Sentry / Bugsnag shape so shipping is a 1:1 mapping.

### Per-tag levels and remote config

Turn on verbose logs for one area of a shipped app without flooding the rest. An override matches a tag domain and everything below it (`data` covers `data.database`), the most specific one wins, and it can lower or raise the threshold:

```swift
logging.registry.minimumLevel = .info
logging.registry.setMinimumLevel(.trace, for: .Data.database)   // verbose for one area
logging.registry.setMinimumLevel(.error, for: .ThirdParty.thirdparty) // quiet a noisy SDK
logging.registry.removeMinimumLevel(for: .Data.database)
```

Filtered calls still return before the message is built. In release builds `debug(_:)` is compiled out, so use `.trace` for verbose logging there. Per-engine levels apply afterwards: a `FileLogEngine(minimumLevel: .info)` still drops trace entries.

SwiftMoLogger never fetches anything. To drive the levels from Firebase Remote Config, LaunchDarkly or your own backend, fetch the config and apply it:

```swift
// e.g. {"data.database": "trace", "thirdparty": "error"}
func apply(levels json: [String: String], to registry: EngineRegistry) {
    let levels = json.compactMapValues(LogLevel.init(name:))  // unknown names are skipped
    registry.levelOverrides = LevelOverrides(levels)          // replaces every override atomically
}
```

### Sampling + rate limiting

```swift
// Keep 1% of trace logs in production
logging.registry.addEngine(SamplingLogEngine(
    wrapping: fileEngine,
    strategy: .perLevel(rates: [.trace: 0.01, .debug: 0.1])
))

// Cap any sink at 50 logs/sec with a 100-event burst
logging.registry.addEngine(RateLimitingLogEngine(
    wrapping: networkEngine,
    permitsPerSecond: 50,
    burst: 100
))
```

Token-bucket rate limiter, thread-local PRNG for sampling — both ~ns-class overhead.

### Remote shipping (Sentry / Datadog / Loki / OpenTelemetry)

```swift
import SwiftMoLoggerRemote

// nil for a malformed DSN, so a bad remote-config value can't crash the app.
if let sentry = SentryLogEngine(
    dsn: URL(string: "https://abc@o123.ingest.sentry.io/456")!,
    release: "1.4.2",
    environment: "production"
) {
    logging.registry.addEngine(sentry)
}

logging.registry.addEngine(DatadogLogEngine(
    apiKey: "<DD_API_KEY>",
    site: .eu1,
    service: "checkout"
))

logging.registry.addEngine(LokiLogEngine(
    endpoint: URL(string: "https://loki.example.com/loki/api/v1/push")!,
    labels: ["job": "ios", "env": "prod"]
))

// Any OpenTelemetry (OTLP/HTTP JSON) endpoint: a Collector, Grafana, Honeycomb, New Relic…
logging.registry.addEngine(OTLPLogEngine(
    endpoint: URL(string: "https://otel.example.com:4318/v1/logs")!,
    serviceName: "shop-ios",
    resource: ["deployment.environment": "production"]
))
```

`OTLPLogEngine` maps levels to OpenTelemetry severities, metadata, tag and source location to attributes, and entries logged inside a `TraceContext` to the record's `traceId`/`spanId`, so logs line up with your backend traces.

All shippers: batch (50–100), debounce (5 s), retry with exponential backoff, cap buffered entries on long offline spells. `log()` is O(1) — network happens off the caller's thread.

### Crash reporters and analytics

SwiftMoLogger depends on no vendor SDK: SwiftPM downloads every dependency a package declares, so a Firebase or Amplitude product would land in every app that uses this one. Instead, `ForwardingLogEngine` hands entries to a closure, and the app keeps its own SDK:

```swift
import FirebaseCrashlytics

// Crashlytics attaches recent log lines to the next crash report.
let crashlytics = ForwardingLogEngine(id: "crashlytics", minimumLevel: .info) { entry in
    Crashlytics.crashlytics().log(entry.formatted())
}
logging.registry.addEngine(RedactingLogEngine(wrapping: crashlytics))
```

The same three lines work for Bugsnag (`Bugsnag.leaveBreadcrumb`), Embrace or any SDK with a log call.

Product analytics (Amplitude, Google Analytics, Mixpanel, PostHog, Segment) answers a different question: what users do, not why the app broke. Track curated events with your analytics SDK directly. When some log entries really are events, forward only those:

```swift
logging.registry.addEngine(ForwardingLogEngine(where: { $0.tag?.domain.hasPrefix("business") == true }) { entry in
    Amplitude.instance.track(eventType: entry.message, eventProperties: entry.metadata.storage.mapValues(\.description))
})
```

The closure runs on the logging thread, so only hand off to the SDK there. Wrap it in `RedactingLogEngine` before anything leaves the device, and remember that analytics may need user consent and App Tracking Transparency.

### Auto network logging

```swift
import SwiftMoLoggerNetwork

let network = NetworkLogger(environment: logging)

// Every task on a session you own:
let session = URLSession(configuration: .default, delegate: network, delegateQueue: nil)

// Or a single request on any session:
let (data, _) = try await URLSession.shared.data(for: request, delegate: network)

// Each request is logged with method/URL/status/duration_ms, breadcrumbs are
// recorded, and the Hub's network waterfall is fed. Sensitive headers are redacted.
```

`NetworkLogger` is a `URLSessionTaskDelegate` you inject where you create sessions; there is no global hook, so only sessions (or requests) you hand it are logged. It only observes: it never changes requests, buffers bodies or affects redirects. `Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`, `X-Auth-Token` and `Proxy-Authorization` values are redacted by default; pass `sensitiveHeaders:` to `NetworkLogger(logger:events:breadcrumbs:sensitiveHeaders:urlRedaction:)` to change the list (start from `NetworkLogger.defaultSensitiveHeaders`).

URLs are redacted too, everywhere they're written (log entries, breadcrumbs, the Hub's waterfall, error descriptions). By default `user:password@` is dropped and the values of common secret query items (`token`, `access_token`, `code`, `api_key`, `signature`, `X-Amz-Signature`, …) become `REDACTED`. Pick another `URLRedaction` per logger:

```swift
NetworkLogger(environment: logging, urlRedaction: .withoutQuery)                    // drop query strings
NetworkLogger(environment: logging, urlRedaction: .redactingQueryItems(URLRedaction.defaultSensitiveQueryItems.union(["otp"])))
NetworkLogger(environment: logging, urlRedaction: .full)                            // local debugging only
```

### Privacy manifest

Each target that uses a required-reason API ships a `PrivacyInfo.xcprivacy`, and Xcode merges them into your app's privacy report:

| Target | Declares |
| --- | --- |
| `SwiftMoLogger` | UserDefaults (CA92.1), FileTimestamp (C617.1), SystemBootTime (35F9.1) |
| `SwiftMoLoggerDiagnostics` | DiskSpace (7D9E.1): free disk space in the bug report the user chooses to send |

Both declare no tracking and no collected data. The package never sends anything off the device by itself. If you add a remote engine (`HTTPLogShipper`, Sentry, Datadog, Loki, …), declare the data you ship in your app's own manifest and App Store privacy details: typically diagnostics and crash data, plus anything your log messages contain.

---

## Distributed tracing (W3C)

Stamp every log entry inside a trace with its trace and span IDs, and your outbound `URLSession` requests with a W3C `traceparent` header. Tie the iOS-side operation directly to the downstream backend trace in Datadog, Honeycomb, OpenTelemetry, etc.

```swift
try await TraceContext.generate().run {
    logger.info("starting checkout")        // carries trace.id / span.id metadata

    var request = URLRequest(url: chargeURL)
    request.addTraceparentHeader()          // traceparent: 00-<traceID>-<childSpanID>-01
    let (data, _) = try await session.data(for: request)
    // …each request you stamp gets the same trace, new child span
}
```

`TraceContext` is a value type — generate fresh roots, spawn child spans, parse inbound headers:

```swift
let ctx = TraceContext.generate()
let parsed = TraceContext.parse(traceparent: incomingHeader)
let child = ctx.childSpan()
```

Backed by `@TaskLocal`, so concurrent tasks see their own trace.

---

## Flight recorder — black box for crashes

```swift
let recorder = FlightRecorder(environment: logging)   // 2-minute window, flushed every 5 s
recorder.start()
```

Persists a rolling 2-minute window of every signal flowing through the environment (logs, breadcrumbs, network, signposts, vitals) to a small file in Caches. It only writes when something new was recorded, and it flushes when the app moves to the background. Pass `redactor:` to scrub entries, breadcrumbs and network events (URL queries are dropped) before anything touches the disk. On next launch:

```swift
if let session = recorder.crashedSession {
    logging.logger.warning("Recovered crashed session: \(session.entries.count) entries")
    uploader.attach(session)
}
```

`crashedSession` is non-nil **only** when the previous run died while it was running in the foreground: a crash, an out-of-memory kill or a watchdog kill. Going to the background marks the session clean, because iOS terminates suspended apps without warning and a user swiping the app away isn't a crash (the trade-off: a crash while running in the background isn't reported either). `start()` captures the previous session before marking the new one as running, so it's safe to read at any point. The exact signals you wish you'd had, after the fact.

Pair it with MetricKit (iOS / macOS) for the crash, hang and diagnostic payloads the OS delivers on the next launch:

```swift
let metricKit = MetricKitCrashReporter(logger: logging.logger)
metricKit.startMonitoring()
```

And for a "Send Bug Report" button, `BugReporter` bundles device info, breadcrumbs, recent logs and the last vitals sample into a directory you can hand to `ShareLink` or an uploader:

```swift
import SwiftMoLoggerDiagnostics

let memory = MemoryLogEngine(capacity: 500)
logging.registry.addEngine(memory)

let reporter = BugReporter(environment: logging, memoryEngine: memory, vitalsMonitor: vitals, appName: "Shop")
let report = try reporter.generate()
// report.directory → ShareLink / UIActivityViewController / custom uploader
```

---

## Error grouping

A `1000`-occurrence retry-spam logged once with `count = 1000`:

```swift
let grouper = ErrorGroupingEngine(
    wrapping: sentryShipper,
    fingerprintMinLevel: .warning,
    emitThreshold: 1   // emit first occurrence per fingerprint
)
logging.registry.addEngine(grouper)
```

Fingerprints by normalising the message (UUIDs → `<uuid>`, hex blobs → `<hex>`, digit runs → `#`, quoted strings → `"…"`), then SHA-256 of the result. Different shapes stay distinct; identical-shape noise collapses.

```swift
let groups = grouper.snapshot()
// → ErrorGroup(count: 1024, exemplar: "User # timed out", firstSeen: …, lastSeen: …)
```

---

## Swift Concurrency

### Task-local ambient context

```swift
try await LogContext.with(["request_id": "req-42", "user_id": "u-123"]) {
    logger.info("fetching profile")   // ← inherits both keys
    try await api.fetchProfile()
    logger.info("profile cached")     // ← still inherits
}
logger.info("outside scope")          // ← clean
```

Backed by `@TaskLocal` — concurrent `Task`s see their own scope without interfering. The registry merges the ambient context at dispatch, so every logger sees it without anything being injected.

### AsyncStream of entries

```swift
Task {
    for await entry in logging.stream.subscribe() where entry.level >= .error {
        await reportToBackend(entry)
    }
}
```

### Combine publisher (alternative)

```swift
let combine = CombineLogPublisher()
logging.registry.addEngine(combine)

combine.publisher
    .filter { $0.level >= .error }
    .sink { entry in /* … */ }
    .store(in: &cancellables)
```

### Signposts for Instruments

```swift
let signposter = logging.signposter   // a Signposter; inject it where you measure

let users = try signposter.measure("loadUsers", tag: .database) {
    try userRepo.all()
}

let response = try await signposter.measureAsync("uploadAvatar") {
    try await uploader.send(image)
}

// Spans that cross function boundaries:
let span = signposter.makeInterval("imageDownload")
defer { span.end() }
```

One call emits an `os_signpost` interval (visible in Instruments' Points of Interest), a log entry with `metadata.elapsed_ms`, **and** a span for the Diagnostics Hub's flame graph.

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
    func testFailureIsLogged() async throws {
        let (logging, logs) = LogEnvironment.recording()
        let service = CheckoutService(log: logging.logger)

        try await service.purchase(invalid: true)

        XCTAssertLogged(.error, contains: "declined", tag: .api, in: logs)
        XCTAssertLogCount(0, atLevel: .fault, in: logs)
    }

    func testPaymentIsLogged() {
        let (log, logs) = MoLogger.recording()   // when the code under test only needs a logger
        CheckoutService(log: log).pay(orderID: "42")
        XCTAssertLogged(.info, contains: "Paying", in: logs)
    }
}
```

Using Swift Testing? The recorder's queries return plain values, so they work with `#expect`:

```swift
import Testing
import SwiftMoLoggerTesting

@Test func declinedPaymentIsLogged() async throws {
    let (log, logs) = MoLogger.recording()
    try await CheckoutService(log: log).purchase(invalid: true)

    #expect(logs.contains(.error, containing: "declined", tag: .api))
    #expect(logs.count(.fault) == 0)
}
```

`entries(_:containing:tag:withMetadataKey:)`, `contains(…)` and `count(…)` take the same filters (level, substring, tag domain, metadata key).

`LogEnvironment.recording()` returns a fresh environment whose only engine (besides its stream) is a `RecordingLogEngine`; `MoLogger.recording()` does the same and hands back just the logger. Inject it into the system under test, then assert on *what* it logged. Nothing global is touched, so every test is isolated and suites are safe to run in parallel.

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
| `URLSession` traffic logging | ✅ | ❌ | ❌ | ❌ |
| Sentry / Datadog / Loki | ✅ | ❌ | ⚠️ | ❌ |
| Sampling + rate limit | ✅ | ❌ | ❌ | ❌ |
| App vitals (CPU/FPS/mem) | ✅ | ❌ | ❌ | ❌ |
| Swift Macros | ✅ | ❌ | ❌ | ❌ |
| `XCTAssertLogged` | ✅ | ❌ | ❌ | ❌ |
| Task-local context | ✅ | ❌ | ❌ | ❌ |
| W3C `traceparent` propagation | ✅ | ❌ | ❌ | ❌ |
| Flight recorder | ✅ | ❌ | ❌ | ❌ |
| Smart error grouping | ✅ | ❌ | ❌ | ❌ |
| Xcode code snippets bundled | ✅ | ❌ | ❌ | ❌ |

**Compared with [Pulse](https://github.com/kean/Pulse).** Pulse is the closest alternative, and it's the better pick if you mainly want a network inspector: it records full request and response bodies, and it has a polished console and a Mac app. SwiftMoLogger's `NetworkLogger` records method, URL, status, timing and sizes, but not bodies. SwiftMoLogger is the pick when you want logging *architecture*: injected loggers with no singletons, fan-out to several engines, redaction and sampling decorators, remote shippers, tracing, a flight recorder, a free Bonjour live tail, and assertions for tests.

Spotted something out of date for another library? Please open an issue. For SwiftMoLogger's own numbers, see [PERFORMANCE.md](PERFORMANCE.md).

---

## Upgrading

**From 3.x:** 4.0 removes every singleton and the static `SwiftMoLogger.*` facade in favour of one injected `LogEnvironment`. The upgrade is mechanical: **[MIGRATION.md](MIGRATION.md)** maps every 3.x call to its 4.0 equivalent.

**From v2:** the table below shows each v2 concept and where it lives now (4.0 API):

| v2 | Now (4.0) | Notes |
|---|---|---|
| `LogEngine.info(message:)` | `LogEngine.log(_:)` | v2 methods kept as default-impls |
| `LogTag` is `enum` | `LogTag` is `struct` + namespaces | All `.api` shorthands preserved |
| `getAllEngines()` | `allEngines()` | Old name kept as deprecated alias |
| info/warn silently dropped in release | always shipped | **Real bug fix** |
| no metadata | `metadata: [:]` on every call | |
| no source location | captured via `#fileID` / `#line` | automatic |
| no AsyncStream | `environment.stream.subscribe()` | |
| no signpost integration | `environment.signposter.measure` | |
| no SwiftUI console | `LogConsoleView(stream:)`, `DiagnosticsHubView(environment:)` | |
| logging through a shared registry | `MoLogger` injected from one `LogEnvironment` | No singletons; see [MIGRATION.md](MIGRATION.md) |

---

## Use with AI coding agents

The repository ships an [agent skill](plugin/skills/swiftmologger/SKILL.md) that teaches AI coding agents to set up SwiftMoLogger the 4.0 way. It covers one injected `LogEnvironment`, which engines belong in debug and which in release builds, redaction, network logging, keeping `LiveSink` debug-only, testing, and the 3.x → 4.0 migration. It also includes an audit script that lists every 3.x call with its replacement and flags release-safety problems:

```bash
python3 plugin/skills/swiftmologger/scripts/audit_logging.py path/to/YourApp
```

**Claude Code**: install it as a plugin:

```
/plugin marketplace add MoElnaggar14/SwiftMoLogger
/plugin install swiftmologger@swiftmologger
```

**Codex and other agents that read `SKILL.md`**: copy the skill into your app's repository:

```bash
git clone --depth 1 https://github.com/MoElnaggar14/SwiftMoLogger /tmp/SwiftMoLogger
mkdir -p .agents/skills && cp -R /tmp/SwiftMoLogger/plugin/skills/swiftmologger .agents/skills/
```

(Use `.claude/skills/` instead of `.agents/skills/` to give it to Claude Code without the plugin.) Agents working on this repository itself read [AGENTS.md](AGENTS.md).

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

## 📚 Article series

A five-part deep dive into the design choices and the production playbook. Every sample uses the 4.0 API. Read in order, or jump to whichever is on fire for you today.

| # | Title | What you'll learn |
|---|---|---|
| 1 | [Why I rewrote iOS logging from scratch](Articles/01-why-rewrite.md) | Where `print`, `os.Logger` and classic loggers fall short, and the principles behind 4.0 |
| 2 | [Sub-µs logging: the performance design](Articles/02-performance.md) | Locking, autoclosures, allocation budget and engine fan-out |
| 3 | [Instruments in your app: building the Diagnostics Hub](Articles/03-diagnostics-hub.md) | How the timeline, waterfall, flame graph and vitals charts compose |
| 4 | [Zero-config debugging with Bonjour and Swift Macros](Articles/04-bonjour-and-macros.md) | The Mac live tail, keeping it debug-only, and the macros |
| 5 | [The production playbook: tracing, redaction, flight recorder](Articles/05-production-playbook.md) | The features that save you on the 3 AM call |

Series index: [Articles/README.md](Articles/README.md).

---

## Xcode code snippets

Five `.codesnippet` files in [`Extras/Snippets/`](Extras/Snippets) for the calls you'll type most often:

| Prefix | Expands to |
|---|---|
| `smlinfo` | `logger.info(…, tag:, metadata:)` |
| `smlerror` | `logger.error(error, tag:, metadata:)` |
| `smlmeasure` | `signposter.measure("name", tag: .performance) { … }` |
| `smlcontext` | `LogContext.with(…) { … }` |
| `smlcrumb` | `breadcrumbs.record(…, category: .userAction)` |

The snippets assume the injected dependency (`logger: MoLogger`, `signposter: Signposter` or `breadcrumbs: BreadcrumbStore`) is in scope.

Install:

```bash
cp Extras/Snippets/*.codesnippet ~/Library/Developer/Xcode/UserData/CodeSnippets/
```

Restart Xcode. The snippets show up in the Snippets Library (`⌘⇧L`) and autocomplete by prefix.

---

## License

MIT. See [LICENSE](LICENSE).

---

<p align="center">
<sub>Built with care by <a href="https://github.com/MoElnaggar14">@MoElnaggar14</a>. If it helped you ship faster, drop a ⭐.</sub>
</p>
