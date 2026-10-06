# Private by default

Issue: [#48](https://github.com/MoElnaggar14/SwiftMoLogger/issues/48), part of the 5.0 roadmap ([#43](https://github.com/MoElnaggar14/SwiftMoLogger/issues/43)). Status: proposal. The breaking part ships in 5.0. The preparation ships in the last 4.x minor.

## Problem

Since 4.3, `\(value, privacy: .private)` hides one value ([per-value-privacy.md](per-value-privacy.md)). A plain `\(value)` is still public, so a forgotten marker leaks the value to every engine: files, remote shippers, the live tail. `os.Logger` defaults the other way, and so should a library whose README says nothing leaves the device unredacted. A forgotten marker should hide data, not leak it.

## End state in 5.0

```swift
log.info("Signed in \(email) on \(device)")              // "Signed in <private> on <private>"
log.info("Opened \(screen, privacy: .public)")           // "Opened Settings"
log.info("Retry \(attempt) of \(limit), ok: \(isOK)")    // "Retry 2 of 5, ok: false"
log.info("Step \(step)")                                 // "Step checkout"  (CheckoutStep: LogPublicValue)
log.notice("Refreshed \(token, privacy: .sensitive)")    // "Refreshed <sensitive>"

log.info(text)                       // error: pass "\(text)" to hide it, or LogMessage(verbatim: text) to show it
log.info(LogMessage(verbatim: text)) // shown as is
#log(logger, "Signed in \(email)")   // "Signed in <private>", same rules
```

- Every level method takes a `LogMessage`. Literal text is public. An interpolated value is private unless its type is declared safe (numbers, `Bool`, `LogPublicValue` types) or the call site says `privacy: .public`.
- `revealsPrivateValues` shows private values in DEBUG builds only. In release they always render as `<private>`.
- Nothing about engines changes. `LogEntry.message` is still the rendered `String`, and hidden values still never reach a `LogEntry`.

## Domain model

### LogPrivacy

`LogPrivacy` keeps its three levels and two masks. 5.0 only changes what an interpolation *without* `privacy:` means:

| Interpolation | 4.x | 5.0 |
|---|---|---|
| `\(x, privacy: .public / .private / .sensitive)` | as marked | as marked |
| `\(n)`, `n` an integer, `Float`, `Double` or `Bool` | public | public |
| `\(x)`, `x: some LogPublicValue` | — | public |
| `\(message)`, `message: LogMessage` | keeps its own privacy | keeps its own privacy |
| `\(x)`, anything else (`String`, `URL`, `UUID`, `Date`, errors, enums, collections) | public | private: `<private>`, revealed by `revealsPrivateValues` |

An unmarked value behaves exactly like `.private`: same placeholder, same reveal rule. There's no new privacy level and no way to tell an unmarked value from a `.private` one after rendering. `.sensitive` stays the only level that is never revealed.

Numbers and `Bool` are public because `os.Logger` does the same, and because counts, durations and status codes are most of what gets interpolated. The cost: a phone number or user ID stored as an `Int` is shown. That's an open question below.

`LogPublicValue` lets a type declare once that its description is safe, instead of marking every call site:

```swift
/// A type whose `description` is safe to log. Interpolated without `privacy:`, it's shown.
public protocol LogPublicValue {}

extension Int: LogPublicValue {}      // and every fixed-width integer, Float, Double, Bool,
extension StaticString: LogPublicValue {} // LogLevel, LogTag
extension Optional: LogPublicValue where Wrapped: LogPublicValue {}

// In the app:
extension CheckoutStep: LogPublicValue {}
```

The interpolation picks the constrained overload when it applies, because a constrained generic is more specialised than an unconstrained one:

```swift
public mutating func appendInterpolation<T>(_ value: T) {                  // private by default
    appendInterpolation(value, privacy: .private)
}
public mutating func appendInterpolation<T: LogPublicValue>(_ value: T) {  // declared safe
    appendLiteral(String(describing: value))
}
```

The conformances are ours (our protocol), so they aren't retroactive and Swift 6 doesn't warn. An app that conforms a type it doesn't own (`UUID`) gets the retroactive-conformance warning, which is the right nudge.

### Literal or interpolated

- **Literal**: the text segments of the string literal at the call site, including multi-line literals. Always public. They are written by the developer and compiled into the binary.
- **Interpolated**: anything inside `\( )`, judged by its static type. `\("constant")` interpolates a `String` and is private; write the text into the literal instead.
- A `LogMessage` built elsewhere (`let m: LogMessage = "Started \(id)"`) carries its decisions with it. Interpolating it into another message keeps them, as today.

### String-typed messages

A `String` value is computed text. The model says computed text is private, but hiding a whole message (`log.info(Messages.started)` showing `<private>`) would be a silent and confusing change. A `String` that is public by fiat would keep the leak this issue closes: `let s = "Signed in \(email)"; log.info(s)`, and every app wrapper like `func track(_ s: String) { log.info(s) }`.

So 5.0 makes the call site decide. The `String` overloads stay, marked unavailable with a message, and the compiler lists every place that passes a `String`:

```swift
@available(*, unavailable, message: """
    Log messages are private by default. Pass "\\(text)" to hide the text, \
    or LogMessage(verbatim: text) to show it.
    """)
func info(_ message: @autoclosure () -> String, tag: LogTag? = nil, …) { fatalError() }
```

Keeping them unavailable rather than deleting them gives the custom error instead of "cannot convert value of type 'String' to 'LogMessage'". The type checker ranks unavailable overloads below every available one (`SK_Unavailable` outranks `SK_NonDefaultLiteral`), so a literal still resolves to `LogMessage` even though `String` is the default literal type. CI must confirm this on 6.1, 6.3 and 6.4, as #39 did for `@_disfavoredOverload`.

`@_disfavoredOverload` comes off the `LogMessage` overloads, since nothing else competes with them. `error(_ error: any Error)` is unchanged as an overload, but its message becomes `"\(error.localizedDescription)"`, so private (open question).

`#log` collapses to one declaration, `macro log(_ logger: MoLogger, _ message: LogMessage, …)`. The `MoLogger?` tie-breaker goes away.

### Metadata

Unchanged in 5.0. Metadata is structured: each key is attached on purpose, its value is typed, and `RedactingLogEngine` already runs over string values. Metadata privacy can't reuse the interpolation, because values arrive as `LogMetadataValue`, not segments. Adding a `.private(…)` case to `LogMetadataValue` would break exhaustive switches in apps and engines, so if we ever want it, 5.0 is the time. The README must say plainly that privacy defaults cover the message, not metadata. That includes the `error` metadata that `error(_:)` adds today.

### Release builds

`revealsPrivateValues` is read only in DEBUG builds of the library. In a release build, the getter returns `false` whatever was set:

```swift
public var revealsPrivateValues: Bool {
    get {
        #if DEBUG
        lock.lock(); defer { lock.unlock() }
        return revealsPrivate
        #else
        return false
        #endif
    }
    set { … }   // stored as before, so tests and DEBUG behave the same
}
```

A Swift package is built in the app's configuration, so this follows the app's DEBUG. A precompiled binary of the library would not; we don't ship one. The audit script's existing rule (`revealsPrivateValues = true` outside `#if DEBUG`) stays as a warning about intent.

## Migration, working backwards

5.0 has to be a mechanical upgrade: every call site that changes meaning is listed before the release, and every call site that stops compiling has a one-line fix in the error message.

### What 4.x ships

1. **The library's own call sites, made explicit.** Additive and valid in 4.x, so 5.0 doesn't change any message the package writes:
   - `MetricKitPayloadLogger`: `\(payload.kind.rawValue, privacy: .public)`.
   - `AutoLogMacro` expansion: `"→ \\(method, privacy: .public)"`. A function name isn't user data. The expansion is plain text, so swift-syntax 509 to 604 doesn't matter.
   - `Signposter`: `\(span.name)` is a `StaticString`, public either way. Mark the formatted duration `privacy: .public`.
   - `LiveSink`: leave `\(error)` unmarked. Private in 5.0 is fine for a status message.
   - `SwiftMoLogHandler` passes swift-log's flattened message as `LogMessage(verbatim:)` (open question).
2. **`LogPublicValue`**, additive. In 4.x the unconstrained overload is still public, so conforming a type changes nothing yet. Apps can conform their enums ahead of time.
3. **An audit rule.** `audit_logging.py --privacy` lists every interpolation without `privacy:` inside a level call or `#log`:

   ```
   Checkout.swift:42: [privacy] \(user.name) renders <private> in 5.0: add privacy: .public if it's safe, or privacy: .private to keep it hidden
   ```

   It skips interpolations it can tell are numeric (integer literals, `.count`). It can't see types, so it lists the rest. Adding either marker settles a line. `--fix-privacy` rewrites only an allowlist to `privacy: .public`: `.rawValue`, names ending in `count`, `Count`, `index`, `ID` or `Id`. IDs are on the list because `RedactingLogEngine` still runs on the result. Anything else needs a person. It must read a call across lines, because calls like `MetricKitPayloadLogger`'s span several. `[privacy]` doesn't change the exit status, so apps' CI doesn't break. Our CI runs `--privacy` on `Sources` and `ExampleApp` and fails on any `[privacy]` line.
4. **An early opt-in: the `PrivateByDefault` package trait.** It turns on exactly the 5.0 behaviour, minus the errors:

   ```swift
   // Package.swift of an app or a wrapper package
   .package(url: "https://github.com/MoElnaggar14/SwiftMoLogger", from: "4.6.0", traits: ["PrivateByDefault"])
   ```

   ```swift
   public mutating func appendInterpolation<T>(_ value: T) {
       #if PrivateByDefault
       appendInterpolation(value, privacy: .private)
       #else
       appendLiteral(String(describing: value))
       #endif
   }
   ```

   Under the trait, `@_disfavoredOverload` moves from the `LogMessage` overloads to the `String` ones, and the `String` ones are deprecated with the 5.0 error text rather than unavailable. Literals resolve to `LogMessage` and hide values. `String` values keep working, shown, with a warning that lists them. A warning instead of an error matters because a trait applies to the whole package graph, including third-party packages that log through SwiftMoLogger.

**Why not a runtime flag** on `EngineRegistry` or `LogEnvironment`. In 4.x a plain literal resolves to the `String` overload at compile time, so it never becomes a `LogMessage` and no runtime setting can reach its values. A runtime flag could only change messages that already use `privacy:` somewhere, which is the silent half-change the 4.3 doc rejected. The decision is made by overload resolution, so the opt-in has to be compile-time.

No 4.x deprecations outside the trait. Deprecating the `String` overloads would warn on every plain literal, because that's the overload they resolve to.

### What 5.0 changes

| Change | Who notices | How they migrate |
|---|---|---|
| Unmarked non-numeric interpolations render `<private>` | output only: no build error | `audit_logging.py --privacy` listed them in 4.x. Add `privacy: .public` or conform the type to `LogPublicValue` |
| `String` overloads of the level methods are unavailable | build error, with the fix in the message | `"\(text)"` (hidden) or `LogMessage(verbatim: text)` (shown). App wrappers should take `LogMessage` |
| `"a" + b` as a message no longer compiles (`+` gives a `String`) | build error | `"a\(b)"` |
| `#log` takes a `LogMessage` and a non-optional `MoLogger` | build error only for `String` values | as above |
| `error(_:)` hides `localizedDescription` (if the open question agrees) | output only | `log.error("\(error.localizedDescription, privacy: .public)")` |
| `revealsPrivateValues` has no effect in release builds | output only, release only | none. The audit already flagged it |

MIGRATION.md gets a 4 → 5 section with this table, joined with #49's removals. No `MIGRATIONS` rows are needed for this issue: no API is renamed, and the compiler error carries the fix. The README, Articles 5, the skill's `references/features.md` and `SKILL.md` move to the new default.

## Performance

- **Filtered calls:** unchanged. The message is still an `@autoclosure`, so a filtered call never runs the interpolation, and unavailable overloads cost nothing at run time.
- **Kept calls in release:** one string. With `revealsPrivateValues` compiled out of release, `LogMessage.StringInterpolation` doesn't need the revealed rendering, so under `#if !DEBUG` it never starts the second string. `hasPrivateValues` is then always false and the registry lock is never read for it. Same cost as a `String` interpolation today.
- **Kept calls in DEBUG:** a message with any private value (now most messages that interpolate a `String`) builds the second rendering and reads the flag under the lock. That doubles string building for those calls, in debug builds only.
- **Numbers:** the `LogPublicValue` overload renders with `String(describing:)`, as today.

PERFORMANCE.md's privacy row and table get `testHotPathPlainInterpolation` (an unmarked `String`, kept) next to the existing `testHotPathWithPrivateValue` and `testFilteredPrivateValue`. The usual rule applies: more than 10% slower than the 4.x `String` path is a bug.

## Swift 6.1 compatibility

- **Traits need `swift-tools-version: 6.1`.** `Package.swift` is on 6.0. CI's floor is already 6.1, so bump it, or add a `Package@swift-6.1.swift` if 6.0 users should keep resolving 4.x.
- **Xcode projects can't enable a dependency's trait** as far as we know (to verify on Xcode 16.4 and 26). An app that isn't itself a package uses a local wrapper package that depends on SwiftMoLogger with the trait.
- **Overload ranking.** Three things must be checked on 6.1, 6.3 and 6.4 in tests that compile real calls: unavailable `String` overload vs literal, the constrained `LogPublicValue` overload vs the unconstrained one inside an interpolation, and messages typed from context (`log.info({ …; return "x \(y)" }())`).
- **`Float16`** is unavailable on Intel Macs. Leave it out of the `LogPublicValue` conformances rather than guard it.

## Alternatives considered

- **Everything interpolated is private, numbers too.** Simplest rule, safest. But it's noisy: every count and duration needs a marker. It also differs from `os.Logger`, which most readers already know.
- **Keep the `String` overloads, documented as public.** No build break, but `String` variables and app wrappers keep leaking silently, and the regex audit can't find them because it can't see types. This is the leak the issue exists to close.
- **Keep the `String` overloads, private as a whole.** Safe, but `log.info(Messages.started)` silently becomes `<private>`, and nobody is told.
- **Delete the `String` overloads** instead of marking them unavailable. Same result with a worse error message.
- **A runtime opt-in flag** on `EngineRegistry` or `LogEnvironment`. It can't reach plain literals in 4.x (see above).
- **A separate opt-in module.** Another module can add overloads but can't make a literal prefer them over `String`, the default literal type.
- **A `Package.swift` environment variable** to define a compilation condition. It isn't reliable when Xcode resolves packages.
- **Carry segments in `LogEntry`** so each engine applies its own default. Rejected in 4.3 for the same reason: `LogEntry` is `Codable` and reaches engines that persist it.

## Decisions

Decided by the maintainer on 2026-10-06.

1. **Numbers and `Bool` are public by default**, like `os.Logger`. An ID stored as an integer is marked `privacy: .private` at the call site.
2. **The `String` overloads become unavailable in 5.0**, with a message that suggests `"\(text)"` to hide the value or `LogMessage(verbatim: text)` to show it, so every call site is decided once.
3. **`LogPublicValue` ships under that name.** Out of the box: the numeric types, `Bool`, `StaticString`, `LogLevel`, `LogTag`, and `Optional` of those. `UUID` and arrays stay private; apps can add conformances.
4. **Release builds ignore `revealsPrivateValues`.** A QA build that needs private values uses a Debug-like configuration.
5. **4.x ships only the audit rule** (`audit_logging.py --privacy`, plus `--fix-privacy` for the safe list). No `PrivateByDefault` package trait, so no tools-version bump and no wrapper package for Xcode apps.
6. **Metadata stays out of privacy in 5.0.** Private metadata values are tracked in a separate issue.
7. **`error(_:)` hides `localizedDescription` in the message.** The error's type name stays public, so entries can still be grouped.
8. **swift-log bridge messages are verbatim and public.** swift-log has its own rules, and its messages arrive already flattened.
9. **`SystemLogger` keeps `.privateInRelease`.** Values are hidden before they reach it; this is defence in depth at no cost.
10. **Breadcrumbs and signpost names follow the same rule in 5.0**, for consistency.
