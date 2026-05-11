# GitFlow for SwiftMoLogger

This repository follows a strict [GitFlow](https://nvie.com/posts/a-successful-git-branching-model/) layout. PRs that don't match the policy are rejected by CI.

## Long-lived branches

| Branch | Purpose | Direct push? |
|---|---|---|
| `main` | Tagged releases only. Every commit is a tagged version. | ❌ via release PR only |
| `develop` | Integration branch. All feature/bugfix PRs land here. | ❌ via PR |

## Short-lived branches

| Prefix | Branches off | Merges into | Naming |
|---|---|---|---|
| `feature/*` | `develop` | `develop` | `feature/<scope>-<kebab-summary>` |
| `bugfix/*` | `develop` | `develop` | `bugfix/<issue-id>-<kebab-summary>` |
| `release/*` | `develop` | `develop` + `main` | `release/<semver>` |
| `hotfix/*` | `main` | `main` + `develop` | `hotfix/<semver>-<kebab-summary>` |

## Active feature branches (v3 work)

- `feature/swift-concurrency` — `AsyncStream`, `Sendable`, ambient context
- `feature/swiftui-console` — `SwiftMoLoggerUI` target, drop-in `LogConsoleView`
- `feature/performance-benchmarks` — `XCTClockMetric` baselines + `PERFORMANCE.md`

## Standard release procedure

```bash
# 1. Cut a release branch off develop
git checkout develop && git pull
git checkout -b release/3.0.0

# 2. Bump version + changelog, push
# (manually edit Package.swift comment / CHANGELOG.md)
git push -u origin release/3.0.0

# 3. Open two PRs from the release branch:
#    a) release/3.0.0 → main   (production-ready merge)
#    b) release/3.0.0 → develop (back-merge of any release fixups)

# 4. Tag main once merged
git checkout main && git pull
git tag -a 3.0.0 -m "SwiftMoLogger 3.0.0"
git push origin 3.0.0
```

## Hotfix procedure

```bash
git checkout main && git pull
git checkout -b hotfix/3.0.1-crash-on-empty-bundleid
# … fix …
git push -u origin hotfix/3.0.1-crash-on-empty-bundleid
# Open PRs → main AND → develop
```

## CI enforcement

`.github/workflows/gitflow.yml` blocks PRs that target the wrong base branch (e.g. a `feature/*` branch trying to merge into `main` instead of `develop`).

## Why this matters here

SwiftMoLogger has external SPM consumers. A regression that lands on `main` is shipped to every adopter on their next `swift package update`. GitFlow gives us a deterministic spot (`develop`) where breaking changes are integrated and stabilised before they can ever reach a tagged release.
