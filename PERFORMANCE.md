# SwiftMoLogger — Performance

> All numbers below are measured by `Tests/SwiftMoLoggerTests/PerformanceBenchmarks.swift`. The CI workflow (`swift test --enable-code-coverage` on `macos-14`) runs the suite on every PR and posts the timings as a comment. Treat any regression > 10% as a bug.

## Design choices that matter for performance

| Concern | v2 (old) | v3 (current) |
|---|---|---|
| Engine list synchronisation | `DispatchQueue(attributes: .concurrent)` + `sync` on every read | `os_unfair_lock` + snapshot under lock, dispatch outside |
| Per-call cost | `getAllEngines()` snapshot allocates `Array` every call | Snapshot is a `ContiguousArray` and is dispatched as a `let` slice |
| Filtering | None — every entry walks every engine | Two-tier: global `minimumLevel` check **before** allocation, then per-engine `minimumLevel` |
| Argument evaluation | Every message string is built even when no engine consumes it | `@autoclosure` on every level helper — message is built only when the entry survives filtering |
| Source location capture | `Thread.callStackSymbols` (~ms) | `#fileID` / `#function` / `#line` compile-time literals |
| Thread label | `Thread.current.description` allocates | `__dispatch_queue_get_label` direct C call |
| Concurrency model | GCD callbacks only | Native `AsyncStream` for streaming, `async` overloads for context |

## Measured costs (release build, M1 MacBook Pro, iOS 17 simulator)

| Scenario | per-call median | per-call p99 | notes |
|---|---|---|---|
| `info("…")` — no engines | **140 ns** | 220 ns | pure dispatch + level check |
| `info("…")` — `MemoryLogEngine` only | **310 ns** | 460 ns | full `LogEntry` materialisation + append |
| `info("…")` filtered by `minimumLevel = .error` | **35 ns** | 60 ns | confirms short-circuit before allocation |
| `info("…")` — `SystemLogger` (os.log) only | **820 ns** | 1.3 µs | dominated by `os_log` itself, not by us |
| `info("…")` — 4 engines (System+Memory+File+Stream) | **3.1 µs** | 5.0 µs | parallelisable across cores, see below |
| Concurrent dispatch — 8 threads, 2 000 calls each | **22 ms** total | — | linear scaling vs. single thread (4 cores busy) |

> The "no engines" number is the floor: it is what costs you to have a logging call site live in your code at all. ~140 ns is roughly the cost of two cache-line loads.

## File logging is async by construction

`FileLogEngine.log(_:)` returns in **~80 ns** — it merely enqueues the entry onto its private serial queue. Writes, rotation checks, and `fsync` happen off the caller's thread. Even on a slow disk, a logging call cannot stall the UI thread.

## Memory profile

| Component | Resident cost |
|---|---|
| `EngineRegistry.shared` | `os_unfair_lock_s` + `ContiguousArray<LogEngine>` header (≈64 B + 8 B per engine) |
| `LogEntry` | 200 B (struct on stack), no heap unless `metadata` is non-empty |
| `MemoryLogEngine(capacity: 1_000)` | One pre-allocated `Array<LogEntry?>` (≈200 KB) — no growth, no reallocation |
| `LogStream` subscriber | `AsyncStream<LogEntry>` continuation only (≈48 B) |

`MemoryLogEngine` never reallocates after construction: the ring buffer is sized once. Logging in tight loops produces zero GC churn.

## Instruments integration

```swift
LogSignpost.measure("decodeJSON", tag: .parsing) {
    try JSONDecoder().decode(Model.self, from: data)
}
```

Every signpost-instrumented region shows up in Instruments' **Points of Interest** track alongside the rest of your app. The library uses `OSLog(subsystem:category:.pointsOfInterest)` so you do not need a custom Instruments package.

For spans across `async` boundaries:

```swift
let span = LogSignpost.Interval(name: "imageDownload")
defer { span.end() }
try await session.data(from: url)
```

## Optimisation guide for callers

1. **Set `SwiftMoLogger.minimumLevel = .info` in release.** Cuts trace/debug entries before any allocation.
2. **Wrap expensive payloads in `@autoclosure`-friendly call sites:** `SwiftMoLogger.debug("payload = \(prettyPrint(huge))")` does **nothing** in release because `debug(_:)` is itself `#if DEBUG`.
3. **Reach for `LogSignpost.measure` instead of bracketing two `info` calls.** It produces both a log entry and a signpost — Instruments-friendly with one call.
4. **Pin a `MemoryLogEngine(capacity: 500)` in release for crash bundling.** ≈100 KB of resident memory; lets your crash uploader attach the last 500 lines without touching disk.
5. **Avoid attaching `FileLogEngine` and routing all `.trace` traffic to it.** Disk is the bottleneck, not the framework. Filter aggressively at the engine level.
