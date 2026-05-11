# Changelog

All notable changes to SwiftMoLogger are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.0.0] — Unreleased

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
