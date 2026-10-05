# Changelog

All notable changes to SwiftMoLogger are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] — Unreleased

Dependency injection everywhere: SwiftMoLogger no longer has any singletons or
global state. See [MIGRATION.md](MIGRATION.md) for the full API map.

### Breaking
- **Safe by default, crash-free on bad input.** `SystemLogger` defaults to `privacy: .privateInRelease` (messages show as `<private>` in release builds' unified log). `TraceContext(traceID:spanID:)`, `SentryLogEngine(dsn:)` and `WebSocketTailEngine(url:)` are failable instead of trapping on malformed input, which often comes from headers or remote config.
- **Swift 6.** Library targets compile in the Swift 6 language mode, with full data-race checking. Requires Xcode 16 or later (swift-tools-version 6.0).
- Removed the static `SwiftMoLogger.*` facade and every `.shared` instance (`EngineRegistry`, `MoLogger`, `BreadcrumbStore`, `NetworkEventStore`, `SignpostEventStore`, `VitalsHistoryStore`, `LogStream`, `CombineLogPublisher`, `AppVitalsMonitor`).
- `LogSignpost` replaced by the injectable `Signposter`; `LogTagged` replaced by `MoLogger.with(tag:)`.
- Network capture is now `NetworkLogger`, a `URLSessionTaskDelegate` you inject. The `URLProtocol`-based capture is gone because the system instantiates those objects and they can't receive dependencies.
- Components take their collaborators in their initializers: `FlightRecorder`, `MetricKitCrashReporter`, `AppVitalsMonitor`, `BugReporter`, `LiveSink`, `HubViewModel` / `DiagnosticsHubView`, `LogConsoleViewModel` / `LogConsoleView`, `SwiftMoLogHandler`.
- Macros take their dependency explicitly: `#log(logger, …)`, `#measure(signposter, …)`. `@AutoLog` uses the type's `logger` property.

### Added
- **`flush()` on every engine** and `EngineRegistry.flush()`. `FileLogEngine` and the remote shippers write or send what they buffer, and decorators forward the call. The protocol requirement has a do-nothing default, so existing engines still compile. Call it when the app moves to the background; the example app does.
- **visionOS 1+** is a supported platform, and CI builds for it.
- The README compares SwiftMoLogger with Pulse: Pulse wins on network request and response bodies.
- `SwiftMoLoggerTesting` re-exports `SwiftMoLogger`, so `import SwiftMoLoggerTesting` is enough in a test file.
- **Agent skill** for Claude Code (installable as a plugin) and Codex: `plugin/skills/swiftmologger`. It teaches AI coding agents the 4.0 setup, which engines belong in debug and which in release, redaction, debug-only `LiveSink`, testing and the 3.x migration. It includes `audit_logging.py`, which lists 3.x calls and release-safety issues and also runs in CI. `AGENTS.md` covers contributors.
- **Swift Testing support.** `RecordingLogEngine` gains `entries(…)`, `contains(…)` and `count(…)` queries (filter by level, substring, tag domain and metadata key) that work with `#expect` as well as XCTest. The XCTest assertions now use them.
- `URLRedaction` for `NetworkLogger`: URLs in log entries, breadcrumbs and network events drop `user:password@` and redact secret query values (`token`, `code`, `api_key`, `signature`, …) by default. `.withoutQuery` and `.full` are also available.
- `LogEnvironment`: the composition root (registry, bound logger, live stream, diagnostics stores, signposter).
- `LogContext.with(_:operation:)` and `TraceContext.run(_:)` for task-local scoping.
- `URLRequest.addTraceparentHeader()`.
- `LogEnvironment.recording()` / `MoLogger.recording()` for isolated, parallel-safe tests.
- `FlightRecorder(redactor:)`: redacts entries before they're persisted, so the crash file never holds raw secrets or PII.
- `FlightRecorder(defaults:)` / `recoverLastSession(from:defaults:)`, so tests and app groups can supply their own `UserDefaults`.
- **Diagnostics Hub accessibility.** The timeline, network waterfall, flame graph and vitals charts have VoiceOver labels and values (the timeline is adjustable), fixed font sizes are replaced with Dynamic Type text styles, and failed requests and slow spans get a warning symbol so status isn't shown by colour alone; see [ACCESSIBILITY.md](ACCESSIBILITY.md).

### Fixed (found in review of the 4.0 changes)
- **`AppVitalsMonitor` leaked and drained battery.** Its display link retained the monitor (so it lived until `stop()`), ran at 120 Hz on ProMotion screens, and switched on app-wide battery monitoring for good. It now uses a weak proxy, caps the link at 60 Hz (FPS is measured against 60), restores the battery-monitoring setting after each read, and cleans up on release.
- **`LiveSink` could ship.** `start()` does nothing in non-DEBUG builds unless you pass `allowInRelease: true`, because it streams every log line unencrypted to the local network.
- Metadata literals with a repeated key keep the last value instead of trapping, and `MemoryLogEngine.recent(_:)` with a negative count returns nothing instead of trapping.
- **The article series used the 3.x API.** All five articles are rewritten for 4.0 and checked against the source.
- **Network failures logged the full failing URL.** The error description was `String(describing:)` of the `URLError`, whose userInfo holds the unredacted URL.
- **Requests weren't logged on the per-task delegate path.** With `session.data(for:delegate:)`, the request was never logged; it's now logged together with the outcome.
- **`FlightRecorder(redactor:)` only redacted entries.** It now also redacts breadcrumbs and network-event errors, and drops URL query strings.
- **`registry.reset()` disconnected `LogEnvironment.stream`.** The stream is now a persistent engine (`EngineRegistry.addPersistentEngine(_:)`), so it survives a reset.

### Changed
- `SwiftMoLogHandler` implements swift-log's `log(event:)` (swift-log 1.12+), and errors passed to swift-log become `error_type` / `error` metadata.
- CI builds the example app.
- `HTTPLogShipper` uses its own ephemeral `URLSession` by default (no cookies or cache; never observed by a `NetworkLogger`).

## [3.1.0] — Not released separately; every fix ships in 4.0.0

A correctness release. No breaking API changes; see "Behaviour changes".

### Added
- **`MoLogger`**, an injectable logger value: a registry, a default tag and bound metadata, with `with(tag:)` / `with(metadata:)` for child loggers. Components can receive their logger instead of reaching for a global, and tests can use isolated registries and run in parallel. The static API now delegates to `MoLogger.shared`.
- `SystemLogger(privacy:)`: `.public` (default, unchanged), `.private`, `.hashed`, or `.privateInRelease` (readable while debugging, redacted in shipped builds), so log messages don't leak into sysdiagnose archives.
- **`SwiftMoLoggerSwiftLog`** product: `SwiftMoLogHandler` routes swift-log `Logger` calls (SwiftNIO, AsyncHTTPClient, gRPC, AWS SDK, …) into SwiftMoLogger engines, with label tags, structured metadata and metadata providers.

### Fixed
- **`FileLogEngine` could grow memory without bound** during a burst of logging, because every entry queued its own write. The backlog is now capped (`maxPendingEntries:`, default 10,000); entries over the cap are dropped, counted in `droppedEntryCount`, and reported in the file with one warning line. A negative `maxRotatedFiles` is treated as 0 instead of trapping.
- **Engines replaced each other by default.** A custom engine's default `engineID` was its type name, and each remote shipper had a fixed ID, so adding a second engine of the same type (or a second shipper to a different endpoint) silently removed the first. Custom engines now default to one ID per instance; shippers are keyed by endpoint (host and path, never credentials), so a second shipper to the *same* endpoint still replaces the first instead of sending everything twice.
- **The default phone rule redacted parts of trace IDs.** It matched digit runs inside hex strings, so about one in eight W3C trace IDs lost a chunk to `[PHONE]` in any redacted sink. It now only matches numbers that aren't part of a longer alphanumeric run.
- **Diagnostics had no privacy manifest.** `BugReporter` reads free disk space, a required-reason API. `SwiftMoLoggerDiagnostics` now ships a `PrivacyInfo.xcprivacy` declaring DiskSpace (7D9E.1).
- **The Flight Recorder rewrote its file every 2 seconds, even when idle** (up to hundreds of MB per hour, enough for iOS disk-write warnings). It now skips the write when nothing new was recorded, flushes every 5 seconds by default, and flushes when the app goes to the background.
- **Every swipe-away looked like a crash.** iOS terminates suspended apps without warning, so the recorder now marks the session clean on entering the background and running again on returning.
- README: live tail needs `NSLocalNetworkUsageDescription` and `NSBonjourServices` (now documented); redaction is opt-in (the README said every line was scrubbed); the privacy section no longer claims remote shipping needs no disclosure.
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
- A custom engine that doesn't override `engineID` no longer replaces another instance of its type. Return a fixed `engineID` if you relied on that. Remote shipper IDs now include their endpoint.
- `FlightRecorder` flushes every 5 s by default (was 2 s) and only when something changed. Pass `flushInterval:` to change it.
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
