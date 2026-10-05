# AGENTS.md

Guidance for AI coding agents (Codex, Claude Code, Cursor, …) working **on this repository**.

> Adding SwiftMoLogger to an app? Use the agent skill instead:
> [`plugin/skills/swiftmologger/SKILL.md`](plugin/skills/swiftmologger/SKILL.md). The README explains how to install it.

## Build and test

```bash
swift build --build-tests
swift test
swiftlint lint
swift run swiftmologger-inspector        # Mac live-tail CLI
```

CI tests with Swift 6.4, 6.3 and 6.1, builds for iOS, macOS, tvOS and watchOS, and builds the macros against swift-syntax 509 through 604. Code must compile on all of them. Guard newer APIs with `#available` and platform-specific code with `#if os(...)` / `#if canImport(...)`.

## Branches

GitFlow is enforced by `.github/workflows/gitflow.yml`. Branch from `develop` as `feature/*` or `bugfix/*`, and open PRs against `develop`. `main` only receives `release/*` and `hotfix/*` merges.

## Layout

- `Sources/SwiftMoLogger`: the core. `LogEnvironment`, `MoLogger`, `EngineRegistry`, engines, redaction, sampling, breadcrumbs, tracing, flight recorder, MetricKit, signposts.
- `Sources/SwiftMoLoggerNetwork`, `…Remote`, `…UI`, `…Diagnostics`, `…Testing`, `…Sugar` (and `…Macros`), `…SwiftLog`, `…Inspector`: opt-in products. See the README's Products table.
- `ExampleApp/`: a SwiftUI demo of every feature.
- `Articles/`: the five-part article series. Keep its code samples on the current API.
- `plugin/`: the Claude Code plugin and agent skill for app developers.

## Rules

- No singletons or static facades. Everything hangs off an injected `LogEnvironment`, and components take the narrowest dependency (`MoLogger`, `BreadcrumbStore`, `Signposter`).
- Library targets compile in the Swift 6 language mode. Don't use `@unchecked Sendable` without a comment explaining why it's safe.
- The logging hot path must not allocate when a level is filtered out. Messages are autoclosures. See PERFORMANCE.md.
- Initialisers that take outside input (URLs, DSNs, trace IDs) return nil rather than trap.
- Nothing leaves the device unless the app adds a remote engine. When you use a new required-reason API, update the target's `PrivacyInfo.xcprivacy`.
- When you change public API, update the README, MIGRATION.md (if it breaks callers), the CHANGELOG, the Articles samples, and the agent skill (`plugin/skills/swiftmologger/`, including the `MIGRATIONS` table in `scripts/audit_logging.py` for removed APIs). CI runs the audit script on `Sources` and `ExampleApp`.
