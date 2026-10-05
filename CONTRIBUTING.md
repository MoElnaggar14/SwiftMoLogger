# Contributing to SwiftMoLogger

Thanks for helping! Bug reports, docs fixes and pull requests are all welcome. By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs and requesting features

- Search [existing issues](https://github.com/MoElnaggar14/SwiftMoLogger/issues) first.
- Open a [bug report](https://github.com/MoElnaggar14/SwiftMoLogger/issues/new?template=bug_report.yml) or a [feature request](https://github.com/MoElnaggar14/SwiftMoLogger/issues/new?template=feature_request.yml). The forms ask for the version, platform and a small reproduction.
- Security problems go through [private reporting](SECURITY.md), never a public issue.

## Development setup

You need Xcode 16.4 or later (Swift 6.1+). CI also tests Swift 6.3 (Xcode 26.6) and Swift 6.4 (Xcode 27).

```bash
git clone https://github.com/MoElnaggar14/SwiftMoLogger.git
cd SwiftMoLogger
swift build --build-tests
swift test
```

Open `Package.swift` in Xcode to work on the package, and lint before pushing:

```bash
brew install swiftlint
swiftlint lint
```

## How the code is organised

| Folder | Product |
| --- | --- |
| `Sources/SwiftMoLogger` | Core: `LogEnvironment`, `MoLogger`, engines, redaction, tracing, Flight Recorder |
| `Sources/SwiftMoLoggerUI` | SwiftUI console and Diagnostics Hub |
| `Sources/SwiftMoLoggerNetwork` | `NetworkLogger` (`URLSessionTaskDelegate`) |
| `Sources/SwiftMoLoggerRemote` | HTTP, Sentry, Datadog and Loki shippers |
| `Sources/SwiftMoLoggerDiagnostics` | `LiveSink`, vitals, `BugReporter`, WebSocket tail |
| `Sources/SwiftMoLoggerSugar`, `…Macros` | `#log`, `#measure`, `@AutoLog` |
| `Sources/SwiftMoLoggerSwiftLog` | swift-log bridge |
| `Sources/SwiftMoLoggerTesting` | Recording engine and XCTest assertions |
| `Sources/SwiftMoLoggerInspector` | `swiftmologger-inspector` Mac CLI |

## Design rules

- **No singletons or global state.** Take dependencies in initialisers; a component gets the narrowest piece of `LogEnvironment` it needs.
- **The hot path stays cheap.** Messages are `@autoclosure`; don't do work in `log()` before the level check. See [PERFORMANCE.md](PERFORMANCE.md).
- **Never crash the host app.** No `fatalError`, `try!` or force unwraps on input from outside the package; prefer failable initialisers.
- **Private by default.** Nothing leaves the device unless the app adds an engine for it. New features that touch logged data must work with redaction.
- **Privacy manifests.** If you use a required-reason API, declare it in that target's `PrivacyInfo.xcprivacy`.

## Tests

Use `LogEnvironment.recording()` or `MoLogger.recording()` so each test owns its environment, and the `LoggingTestCase` base class in `Tests/SwiftMoLoggerTests`. Every bug fix needs a regression test.

## Pull requests

1. Branch from `develop` as `feature/<scope>-<summary>` or `bugfix/<issue>-<summary>`, and open the pull request against `develop`. CI checks the branch layout; see [GITFLOW.md](GITFLOW.md). Keep the change focused and explain *why* in the description (the pull request template will guide you).
2. Add or update tests, docs (README, DocC comments) and `CHANGELOG.md` under the next version.
3. Breaking changes need an entry in `MIGRATION.md`.
4. Make sure CI is green: tests on three Swift versions, builds for iOS, Mac Catalyst, tvOS and watchOS, and SwiftLint.

Commit messages and pull request titles follow [Conventional Commits](https://www.conventionalcommits.org): `fix: …`, `feat: …`, `docs: …`, `feat!: …` for breaking changes.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
