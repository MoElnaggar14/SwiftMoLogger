# Changelog

All notable changes to SwiftMoLogger are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] — Unreleased

Dependency injection everywhere: SwiftMoLogger no longer has any singletons or
global state. See [MIGRATION.md](MIGRATION.md) for the full API map.

### Breaking
- **Swift 6.** Library targets compile in the Swift 6 language mode, with full data-race checking. Requires Xcode 16 or later (swift-tools-version 6.0).
- Removed the static `SwiftMoLogger.*` facade and every `.shared` instance (`EngineRegistry`, `MoLogger`, `BreadcrumbStore`, `NetworkEventStore`, `SignpostEventStore`, `VitalsHistoryStore`, `LogStream`, `CombineLogPublisher`, `AppVitalsMonitor`).
- `LogSignpost` replaced by the injectable `Signposter`; `LogTagged` replaced by `MoLogger.with(tag:)`.
- Network capture is now `NetworkLogger`, a `URLSessionTaskDelegate` you inject. The `URLProtocol`-based capture is gone because the system instantiates those objects and they can't receive dependencies.
- Components take their collaborators in their initializers: `FlightRecorder`, `MetricKitCrashReporter`, `AppVitalsMonitor`, `BugReporter`, `LiveSink`, `HubViewModel` / `DiagnosticsHubView`, `LogConsoleViewModel` / `LogConsoleView`, `SwiftMoLogHandler`.
- Macros take their dependency explicitly: `#log(logger, …)`, `#measure(signposter, …)`. `@AutoLog` uses the type's `logger` property.

### Added
- `URLRedaction` for `NetworkLogger`: URLs in log entries, breadcrumbs and network events drop `user:password@` and redact secret query values (`token`, `code`, `api_key`, `signature`, …) by default. `.withoutQuery` and `.full` are also available.
- `LogEnvironment`: the composition root (registry, bound logger, live stream, diagnostics stores, signposter).
- `LogContext.with(_:operation:)` and `TraceContext.run(_:)` for task-local scoping.
- `URLRequest.addTraceparentHeader()`.
- `LogEnvironment.recording()` / `MoLogger.recording()` for isolated, parallel-safe tests.
- `FlightRecorder(redactor:)`: redacts entries before they're persisted, so the crash file never holds raw secrets or PII.
- `FlightRecorder(defaults:)` / `recoverLastSession(from:defaults:)`, so tests and app groups can supply their own `UserDefaults`.

### Fixed (found in review of the 4.0 changes)
- **Network failures logged the full failing URL.** The error description was `String(describing:)` of the `URLError`, whose userInfo holds the unredacted URL.
- **Requests weren't logged on the per-task delegate path.** With `session.data(for:delegate:)`, the request was never logged; it's now logged together with the outcome.
- **`FlightRecorder(redactor:)` only redacted entries.** It now also redacts breadcrumbs and network-event errors, and drops URL query strings.
- **`registry.reset()` disconnected `LogEnvironment.stream`.** The stream is now a persistent engine (`EngineRegistry.addPersistentEngine(_:)`), so it survives a reset.

### Changed
- `SwiftMoLogHandler` implements swift-log's `log(event:)` (swift-log 1.12+), and errors passed to swift-log become `error_type` / `error` metadata.
- CI builds the example app.
- `HTTPLogShipper` uses its own ephemeral `URLSession` by default (no cookies or cache; never observed by a `NetworkLogger`).

## [3.1.0] — Unreleased

A correctness release. No breaking API changes; see "Behaviour changes".

### Added
- **`MoLogger`**, an injectable logger value: a registry, a default tag and bound metadata, with `with(tag:)` / `with(metadata:)` for child loggers. Components can receive their logger instead of reaching for a global, and tests can use isolated registries and run in parallel. The static API now delegates to `MoLogger.shared`.
- `SystemLogger(privacy:)`: `.public` (default, unchanged), `.private`, `.hashed`, or `.privateInRelease` (readable while debugging, redacted in shipped builds), so log messages don't leak into sysdiagnose archives.
- **`SwiftMoLoggerSwiftLog`** product: `SwiftMoLogHandler` routes swift-log `Logger` calls (SwiftNIO, AsyncHTTPClient, gRPC, AWS SDK, …) into SwiftMoLogger engines, with label tags, structured metadata and metadata providers.

### Fixed
- **Hub leaked memory engines.** Each `HubViewModel` left its memory engine registered after it went away; it now removes it.
- **Recorders could mark each other's sessions as clean.** Each `FlightRecorder` now keeps its own "session alive" flag (keyed by file), and a released recorder unregisters its engine.
- **Two `FileLogEngine`s on one file could interleave bytes.** Files are now opened in append mode.
- **`AppVitalsMonitor` could leak a running display link** when `stop()` raced `start()`.
- **Locks were undefined behaviour.** Thirteen types took `&lock` on a stored `os_unfair_lock_s`. Swift doesn't guarantee a stable address for that, so the lock could silently become a no-op. All of them now use a heap-allocated `UnfairLock`.
- **Engines replaced each other.** `MemoryLogEngine` and `RecordingLogEngine` had fixed IDs, so the Flight Recorder's memory engine swapped out yours (or vice versa), and the Diagnostics Hub's Logs tab stayed empty when you'd already registered one. IDs are now unique per instance. Pass `id:` to opt back into de-duplication.
- `FileLogEngine` IDs are now keyed by full path, so same-named files in different directories no longer collide.
- **The system-logger guard used its position.** `removeEngine(at: 0)` refused to remove whatever happened to be first (after `removeAllEngines()` that's a user engine). The registry's default system logger is now protected by identity.
- **`enableRedaction` dropped logs.** It removed every engine and then re-added them. It's now a single atomic `replaceEngine(id:with:)`.
- **Wrong source column.** Level helpers didn't forward `#column`, and `LogSignpost` logged with its own file and line. Both now report the caller.
- **`LogTag` lost its domain when persisted.** Tags encoded as a bare string, so `LogTag.api` came back with domain `"api"`. Tags now encode `{rawValue, domain}`, and the old format still decodes. The Inspector's tag column works again.
- **Persisted timestamps dropped milliseconds.** The new `.iso8601WithFractionalSeconds` strategies keep them, and still decode whole-second dates.
- **`FileLogEngine`:**
  - `maxRotatedFiles: 0` crashed (`1...0`).
  - A failed rotation dropped all later writes.
  - Queued writes were lost if the engine was released early.
- **`FlightRecorder`:**
  - After `start → stop → start`, the next `stop()` did nothing, so the next launch reported a false crash.
  - `recoverLastSession()` after `start()` always reported a crash. Use the new `crashedSession` property.
  - The timer was accessed from two threads.
  - A custom `fileURL` inside a folder that didn't exist yet silently recorded nothing.
- `ErrorGroupingEngine` grew without bound. New `maxGroups:` parameter (default 1,000) evicts the least recently seen group.
- `AppVitalsMonitor` leaked a mach port per thread on every CPU sample.
- `WebSocketTailEngine` was never deallocated: `URLSession` retains its delegate. `disconnect()` now invalidates the session.
- `LogSignpost.Interval.end()` had a data race on its "ended" flag.
- **`SwiftMoLoggerUI` and `SwiftMoLoggerDiagnostics` didn't compile for tvOS or watchOS**, despite the declared platforms. Controls with no equivalent on those platforms now degrade gracefully (for example, the timeline scrubber uses step buttons on tvOS).
- **Network logging broke the `URLProtocol` contract.** Client callbacks arrived on the child session's queue and could fire after `stopLoading()`. They're now delivered on the loading thread, and never after stop.
- **Log shipping fed itself.** With `NetworkLogger.installOnSharedSession()` and a shipper on `URLSession.shared`, every shipped batch was logged and shipped again. Shippers now mark their requests with the new `URLRequest.excludeFromNetworkLogging()`.
- `NetworkLoggingProtocol.sensitiveHeaders` is now lock-protected.

### Changed
- **Ready for Swift 6.4 / Xcode 27.** CI tests with Swift 6.4 (Xcode 27), 6.3 (Xcode 26.6) and 6.1 (Xcode 16.4), and the swift-syntax range now goes up to 604 (`509.0.0..<605.0.0`), so apps on Swift 6.3 or 6.4 don't hit a dependency conflict.
- PR validation, dependency and release workflows move off the retired Xcode 15.4 onto the latest Xcode. The secret scan now looks for hard-coded credential values instead of failing on any mention of "token" or "password".
- CI: rebuilt on the latest Xcode. It builds every library for iOS, Mac Catalyst, tvOS and watchOS, tests against the newest swift-syntax, and builds DocC. The always-failing manifest grep and the masked iOS test step are gone.

### Behaviour changes
- `MemoryLogEngine().engineID` and `RecordingLogEngine().engineID` are no longer constants. If you removed one with `removeEngine(id: "swiftmologger.memory")`, use `removeEngine(id: engine.engineID)` or construct it with `MemoryLogEngine(id:)`.

## [3.0.0] — 2026-05-11

Major release. Complete rewrite around structured `LogEntry`, Swift Concurrency, and a multi-product architecture. See the [article series](Articles/) for the design rationale.

### Headline features

- **Diagnostics Hub** (`SwiftMoLoggerUI`) — in-app SwiftUI dashboard with
  timeline scrubber, network waterfall, signpost flame graph, vitals
  charts, and breadcrumb trail.
- **Bonjour live tail** (`SwiftMoLoggerDiagnostics` + `swiftmologger-inspector`
  executable) — zero-config multi-device terminal tail over the LAN.
- **Swift Macros** (`SwiftMoLoggerSugar`) — `#log` / `#measure` / `@AutoLog`.
- **W3C distributed tracing** — `TraceContext`, `traceparent` header
  auto-injection on every `URLSession` request.
- **Flight recorder** — rolling 2-minute black box persisted to disk;
  `FlightRecorder.recoverLastSession()` returns the last snapshot only
  when the previous run crashed.
- **Error grouping** — `ErrorGroupingEngine` collapses identical-shape
  noise by fingerprint (UUIDs → `<uuid>`, digit runs → `#`, …).

### Production hardening

### Added

- **`LogLevel` enum** with eight levels (`trace`, `debug`, `info`, `notice`,
  `warning`, `error`, `critical`, `fault`), mapping cleanly onto `OSLogType`.
- **`LogEntry`** — structured, `Sendable`, `Codable` value type that carries
  level, tag, message, metadata, source location, and thread name.
- **`LogMetadata`** — JSON-compatible structured payloads on every call.
- **`SourceLocation`** capture via `#fileID` / `#function` / `#line` —
  automatic, no perf hit.
- **Task-local ambient context** (`SwiftMoLogger.withContext { … }`) backed
  by `@TaskLocal` so concurrent `Task`s never trample each other's context.
- **`AsyncStream` log streaming** — `SwiftMoLogger.stream()` returns a live
  `AsyncStream<LogEntry>` of every log event.
- **`SwiftMoLoggerUI` product** — drop-in `LogConsoleView` SwiftUI view with
  level filter, search, pause, auto-scroll. Plus headless
  `LogConsoleViewModel`.
- **`LogSignpost`** — `measure` / `measureAsync` / `Interval` for one-call
  Instruments integration plus an automatic timing log entry.
- **`MemoryLogEngine`** in `Sources/` — bounded ring buffer with O(1)
  append, lock-free counters, filter helpers.
- **`FileLogEngine`** in `Sources/` — JSON-Lines, async writes, size-based
  rotation.
- **Engine `engineID`** + **`removeEngine(id:)`** for identity-based removal
  and idempotent `addEngine`.
- **Global `minimumLevel`** filter at the registry — short-circuits before
  any allocation.
- **`LogTag` namespaces** (`LogTag.Network.api`, …) — flat shorthands kept.
- **GitFlow workflow** + `GITFLOW.md` + branch-policy CI workflow.
- **`PERFORMANCE.md`** with measured baselines + design notes.
- **Performance benchmark target** (`PerformanceBenchmarks.swift`).

### Changed

- **`SystemLogger`** now uses `os.Logger` for all levels — previously
  `info()` and `warn()` were wrapped in `#if DEBUG` and silently became
  no-ops in release builds.
- **`LogTag`** is a `struct` (was an `enum`) so callers can build custom
  tags via `LogTag.custom("Feature")`. All v2 case shorthands still work.
- **`EngineRegistry`** switched from a concurrent `DispatchQueue` to
  `os_unfair_lock`. Reads are ~3× cheaper, no allocation per call.
- **`LogEngine` protocol** requires `log(_:)` as the single source of truth
  and offers default `info` / `warn` / `error` overloads forwarding to it.
- **Engine `minimumLevel`** is `let` (was `var`) so the `@unchecked
  Sendable` claim is no longer a lie.

### Fixed

- info/warn entries were silently dropped on release builds — they now
  reach `os.Logger` as documented.
- `MetricKitCrashReporter.triggerTestCrash()` is now `public` (was
  internal despite the README documenting it as public).
- `MetricKit` is now properly gated to platforms where it actually exists
  (`iOS` + `macOS`); the watchOS / tvOS build no longer fails on the
  import.
- README docs no longer reference engines that don't exist in `Sources/`.

### Removed

- `LogTag` no longer conforms to `CaseIterable` (now a struct). Existing
  shorthands (`.api`, `.database`, etc.) are preserved as static
  properties.

### Deprecated

- `EngineRegistry.getAllEngines()` → use `allEngines()`.
- `SwiftMoLogger.getAllEngines()` / `getEngines()` → use `allEngines()`.

## [2.0.0] — 2025-01

Initial multi-engine release. Superseded by v3; the architectural defects
that motivated the rewrite are catalogued under "Fixed" above.

## [1.0.0] — 2025-01-17

Initial release.
