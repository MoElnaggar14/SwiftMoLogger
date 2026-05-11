# SwiftMoLogger 3.0.0

Complete rewrite around structured `LogEntry`, Swift Concurrency, and a multi-product architecture. The logging package iOS teams wish they'd written.

## ✨ Headline features

- **🔭 Diagnostics Hub** — drop `DiagnosticsHubView()` into any debug screen and get Instruments + Charles + Console inside your app: timeline scrubber, network waterfall, signpost flame graph, vitals charts, breadcrumb trail.
- **📡 Bonjour live tail** — zero-config Mac CLI (`swift run swiftmologger-inspector`) auto-discovers every device on the LAN and pretty-prints their logs.
- **✨ Swift Macros** — `#log`, `#measure`, `@AutoLog` for zero-boilerplate call sites (opt-in via `SwiftMoLoggerSugar`).
- **🛰 W3C distributed tracing** — `TraceContext` + automatic `traceparent` injection on every `URLSession` request. iOS spans show up next to your backend trace.
- **📼 Flight recorder** — rolling 2-minute black box on disk; `FlightRecorder.recoverLastSession()` returns the snapshot only when the previous run crashed.
- **🪞 Error grouping** — `ErrorGroupingEngine` collapses identical-shape noise by SHA-256 fingerprint of the normalised message.

## 🛡 Production hardening

- **PII / secret redaction** — JWT, Bearer/Basic tokens, AWS/GCP keys, emails, credit cards, IPv4, UUIDs, phone numbers, with custom rule support.
- **Sampling + token-bucket rate limiting** — protect noisy sinks from cascading failures.
- **Remote shipping** — ready-made `SentryLogEngine`, `DatadogLogEngine`, `LokiLogEngine`. Batching, debounce, retry with exponential backoff.
- **Auto `URLSession` capture** — install one `URLProtocol`, every request is logged with method/URL/status/duration_ms, sensitive headers stripped.
- **Privacy manifest** (`PrivacyInfo.xcprivacy`) bundled.
- **MetricKit crash + hang capture** gated to platforms where MetricKit actually exists.
- **Bug report bundler** — one-call zip of logs + breadcrumbs + vitals + device info ready for share sheet.
- **App vitals monitor** — periodic memory/CPU/FPS/thermal samples.

## 🚀 Swift Concurrency

- **`AsyncStream<LogEntry>`** of every log entry via `SwiftMoLogger.stream()`.
- **Combine publisher** alternative via `SwiftMoLogger.publisher()`.
- **Task-local ambient context** via `SwiftMoLogger.withContext { … }` (`@TaskLocal`-backed so concurrent Tasks never trample each other).
- **`Sendable` everywhere** — `LogEntry`, `LogLevel`, `LogTag`, `LogMetadata`, `SourceLocation`.

## 🧪 Testing

- **`SwiftMoLoggerTesting`** target with `RecordingLogEngine` and `XCTAssertLogged` / `XCTAssertNotLogged` / `XCTAssertLogCount` helpers.

## 🚀 Performance

| Scenario | per-call median |
|---|---|
| `info()` — no engines | **~140 ns** |
| `info()` — `MemoryLogEngine` only | **~310 ns** |
| `info()` filtered by `minimumLevel` | **~35 ns** |
| Concurrent 8 threads × 2 000 calls | linear scaling, ~22 ms total |

See [`PERFORMANCE.md`](PERFORMANCE.md) for the full benchmark table and design rationale.

## 📚 Article series

A 5-part deep-dive in [`Articles/`](Articles/) covers the design choices behind v3:

1. [Why I rewrote iOS logging from scratch](Articles/01-why-rewrite.md)
2. [Sub-µs logging: the performance design](Articles/02-performance.md)
3. [Instruments in your app: building Diagnostics Hub](Articles/03-diagnostics-hub.md)
4. [Zero-config debugging with Bonjour and Swift Macros](Articles/04-bonjour-and-macros.md)
5. [The production playbook: tracing, redaction, flight recorder](Articles/05-production-playbook.md)

## 📦 Products

| Product | Use case |
|---|---|
| `SwiftMoLogger` | Core, always |
| `SwiftMoLoggerUI` | SwiftUI console + Diagnostics Hub |
| `SwiftMoLoggerNetwork` | URLSession auto-capture |
| `SwiftMoLoggerRemote` | Sentry / Datadog / Loki shippers |
| `SwiftMoLoggerDiagnostics` | Bug reports, vitals, Bonjour LiveSink |
| `SwiftMoLoggerTesting` | XCTest helpers |
| `SwiftMoLoggerSugar` | Swift Macros wrapper |
| `swiftmologger-inspector` | Mac CLI executable for live tail |

## 🔧 Install

```swift
.package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "3.0.0")
```

## 📋 Requirements

- Swift 5.9+ (Xcode 15.2+ for `swift-syntax` 509, Xcode 15.3+ for 510, Xcode 16 for 600)
- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+

## 🔄 Migration from v2

Most v2 APIs work unchanged. The breaking changes are documented in the [README migration table](README.md#migration-from-v2). Notable:

- `LogTag` is now a `struct` with namespaces (`LogTag.Network.api`) — all flat shorthands (`.api`, `.database`) preserved.
- `LogEngine` requires `log(_:)` as the single source of truth; v2 `info/warn/error` methods retained as default implementations.
- **Bug fix:** info/warn entries no longer silently dropped on release builds (v2 wrapped them in `#if DEBUG`).
- `getAllEngines()` → `allEngines()` (old name kept as deprecated alias).

## 🙏 Credits

Built by [@MoElnaggar14](https://github.com/MoElnaggar14). If it helped you ship faster, drop a ⭐.

---

**Full changelog:** [CHANGELOG.md](CHANGELOG.md)
**Diff:** `v2.0.0…3.0.0`
