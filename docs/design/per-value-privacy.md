# Per-value privacy in log messages

Issue: [#21](https://github.com/MoElnaggar14/SwiftMoLogger/issues/21). Status: implemented, additive, targeted at the next 4.x minor release.

## Problem

`os.Logger` lets you write `logger.info("Signed in \(email, privacy: .private)")`: the message stays readable and only the sensitive value is hidden. In SwiftMoLogger, messages are plain `String`s, so privacy can only be set per engine (`SystemLogger(privacy:)`) or by regex (`Redactor`). Both work on the whole message after the values have already been mixed into it.

## Summary

```swift
log.info("Signed in \(email, privacy: .private) on \(device)")   // "Signed in <private> on iPhone"
log.info("Account \(userID, privacy: .private(mask: .hash))")    // "Account <hash:07ee7e07b4b19223>"
log.notice("Refreshed \(token, privacy: .sensitive)")            // "Refreshed <sensitive>"
```

- `LogMessage: ExpressibleByStringInterpolation`, with an interpolation that accepts `privacy: LogPrivacy`.
- `MoLogger` gets `LogMessage` overloads of `log`, `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical` and `fault`, **next to** the `String` ones.
- `MoLogger` renders the message to a `String` before it creates the `LogEntry`. `LogEntry` and the `LogEngine` protocol don't change, and no engine ever holds a hidden value.
- `EngineRegistry.revealsPrivateValues` (default `false`) shows `.private` values, for DEBUG builds. `.sensitive` values are never shown.

No existing call site changes meaning, so this ships in 4.x without a migration.

## The message type

```swift
public struct LogPrivacy: Sendable, Hashable {
    public enum Mask { case none, hash }
    public static let `public`, `private`, sensitive
    public static func `private`(mask: Mask) -> LogPrivacy
    public static func sensitive(mask: Mask) -> LogPrivacy
}

public struct LogMessage: Sendable, Hashable, ExpressibleByStringInterpolation, CustomStringConvertible {
    public init(verbatim: String)
    public var hasPrivateValues: Bool
    public func rendered(revealingPrivateValues: Bool = false) -> String
}
```

The names follow `OSLogPrivacy`, but it's SwiftMoLogger's own type: `os.Logger`'s interpolation is compiler-checked at build time and can't be stored or forwarded.

| Privacy | Rendered as | With `revealsPrivateValues` |
|---|---|---|
| none, or `.public` | the value | the value |
| `.private` | `<private>` | the value |
| `.sensitive` | `<sensitive>` | `<sensitive>` |
| `.private(mask: .hash)` | `<hash:…>` | the value |
| `.sensitive(mask: .hash)` | `<hash:…>` | `<hash:…>` |

**Plain interpolations are public.** `os.Logger` treats dynamic strings as private by default. SwiftMoLogger keeps today's behaviour instead, so `"x \(y)"` renders the same whether it is a `String` or a `LogMessage`. Making the default private would be a silent behaviour change for every message that happens to also use `privacy:`. Engine privacy (`SystemLogger(privacy: .privateInRelease)`) and redaction still apply on top.

**The hash** is 64-bit FNV-1a over the value's UTF-8 bytes, as 16 hex digits. `Hasher` is seeded per process, so it can't correlate across launches; CryptoKit would be overkill. The hash is for correlating entries, not for secrecy: short or guessable values (emails, phone numbers, small integer IDs) can be recovered by hashing candidates. The README and doc comments say so.

**Storage.** `LogMessage` stores two strings, not a list of segments: the redacted rendering, and the revealed rendering only once the first `.private` value appears. A message without private values costs one string, like a `String` interpolation. Interpolating one `LogMessage` into another keeps its hidden values hidden.

## Overload resolution: why existing call sites don't change

Each level method now has a `String` overload and a `LogMessage` overload, both `@autoclosure`. The `LogMessage` overloads are marked `@_disfavoredOverload`: when both overloads type-check, the compiler picks the `String` one. The cases:

| Call | Viable overloads | Chosen |
|---|---|---|
| `log.info(text)` with `text: String` | `String` | `String` |
| `log.info("literal")` | both | `String` |
| `log.info("x \(y)")` | both | `String` |
| `log.info({ …; return "x" }())`, or any expression typed from context | both | `String` |
| `log.info("x \(y, privacy: .private)")` | `LogMessage` only: `DefaultStringInterpolation` has no `appendInterpolation(_:privacy:)` | `LogMessage` |
| `log.info(message)` with `message: LogMessage` | `LogMessage` | `LogMessage` |
| `log.error(someError)` | the existing `any Error` overload | unchanged |

Every call that compiled before 4.3 therefore resolves exactly as it did. The fifth row relies on the type checker solving interpolation segments together with the call, so a segment that doesn't fit rules out the `String` overload instead of failing the whole expression; the tests call every level method this way on Swift 6.1, 6.3 and 6.4.

Why the attribute is needed: without it, an expression whose type is inferred from context (a closure called inline, for example) type-checks equally well as `String` and as `LogMessage`, and the call is ambiguous. The first CI run of this branch hit exactly that in two existing tests.

Rejected alternatives:

- **Replacing the `String` parameters with `LogMessage`** (the issue's original plan). A literal still works, but `log.info(text)` with a `String` variable would need `LogMessage(verbatim:)`. That breaks callers for no benefit, since the overload achieves the same thing.
- **`@_disfavoredOverload` on the `String` overloads** instead. That would send every plain literal through `LogMessage`, break apps that extend `DefaultStringInterpolation` with their own `appendInterpolation`, and cost every call the `LogMessage` path for nothing.
- **No attribute.** Breaks calls whose argument type comes from context, as above.

`@_disfavoredOverload` is underscored but stable in practice (SwiftUI's own API relies on it). Known edge: an app that adds its own `appendInterpolation(_:privacy:)` to `DefaultStringInterpolation` would keep getting the `String` overload, so its `privacy:` segments would not be hidden by SwiftMoLogger.

## Rendering per engine

Rendering happens once, in `MoLogger.log(_:_:…)`, after the level filter. Engines receive `LogEntry.message` as before.

- **`SystemLogger`.** `os_log` privacy can't be chosen per value at run time: `os_log` needs a `StaticString` format, and `os.Logger` needs an `OSLogMessage` that only the compiler can build from a literal at the call site. Forwarding a `LogMessage` into `os.Logger` with per-segment privacy is therefore impossible. `SystemLogger` gets the pre-redacted text, and its own `privacy` still applies to the whole message (so `.privateInRelease` still hides everything in release).
- **File, memory, stream, live tail, remote shippers.** They get the pre-redacted text. Nothing to change.
- **`RedactingLogEngine`.** Runs on the rendered text, so it still catches values that weren't marked.

**Why `LogEntry` doesn't carry the segments.** Keeping the raw values on the entry would let `SystemLogger` show them to a debugger, but `LogEntry` is `Codable` and fans out to every engine, so a file or remote engine could persist the raw values. Hidden values never reaching an engine is the guarantee that makes the feature worth having. It also keeps `LogEntry`'s shape and its decoding of older files unchanged.

## Revealing private values in DEBUG

`os_log` shows private values when a debugger is attached. The equivalent here is a registry flag:

```swift
#if DEBUG
logging.registry.revealsPrivateValues = true
#endif
```

It's a registry setting rather than per engine because rendering happens once, before fan-out; per-engine reveal would need the raw values on the entry (see above). It defaults to `false`, `reset()` clears it, and it's read under the registry lock only when a kept message has private values. `.sensitive` values ignore it. The agent skill's audit script flags `revealsPrivateValues = true` outside `#if DEBUG`.

## Cost

- **Filtered calls:** unchanged. The `LogMessage` is an `@autoclosure`, so a filtered call never runs the interpolation, and `debug(_:)` is still compiled out of release builds. `testFilteredPrivateValue` covers it.
- **Kept calls without private values:** one string, built like a `String` interpolation.
- **Kept calls with private values:** a second string for the revealed rendering, and one lock to read `revealsPrivateValues`. Placeholders are short literals; the hash is a single pass over the value's bytes. `testHotPathWithPrivateValue` measures it.

## Migration

None. Existing code compiles and behaves as before, and adopting the feature is a per-call-site edit (add `privacy:` to the interpolation).

What a 5.0 could still change, if wanted:

- Make plain interpolations in a `LogMessage` private by default, like `os.Logger`. That's only meaningful if every message is a `LogMessage`, which means replacing the `String` overloads and asking `String` variables to use `LogMessage(verbatim:)`.
- Carry privacy into engines that can use it (for example structured fields for a remote engine), if a way is found to do it without handing raw values to engines that persist entries.

## Follow-up: `#log` ([#45](https://github.com/MoElnaggar14/SwiftMoLogger/issues/45))

`#log(logger, "Signed in \(email, privacy: .private)")` compiles and logs `Signed in <private>`.

The macro's expansion was already right: it passes the message expression through unchanged to `logger.log(level, message, …)`, where the `String` and disfavored `LogMessage` overloads above decide. What stopped it was the declaration, whose message parameter is a `String`, so the privacy literal failed to type-check before expansion. The fix is a second declaration with a `LogMessage` message and the same `LogMacro` implementation:

```swift
public macro log(_ logger: MoLogger,  _ message: String,     level: LogLevel = .info, tag: LogTag? = nil)
public macro log(_ logger: MoLogger?, _ message: LogMessage, level: LogLevel = .info, tag: LogTag? = nil)
```

**Why the logger is optional in the second one.** Macros are resolved like functions, so a plain literal or an expression typed from context type-checks against both declarations. A literal still picks the `String` one (a literal of its default type scores better), but `#log(logger, { …; return "x" }())` would be ambiguous, which is what broke #39's first CI run for the functions. The functions fix that with `@_disfavoredOverload`, but the compiler only allows that attribute on functions, properties and subscripts (`DeclAttr.def`: `OnAbstractFunction | OnVar | OnSubscript`), not on macros. Instead, the `LogMessage` declaration takes `MoLogger?`: every call to it needs a value-to-optional conversion, which the type checker scores as worse, so whenever both declarations type-check the `String` one wins. Only a message that can't be a `String` (a `privacy:` literal or a `LogMessage` value) resolves to the second one. Either way the expansion is the same text, so which declaration wins never changes what runs.

Rejected alternatives:

- **One declaration with a `LogMessage` message.** `#log(logger, text)` with a `String` variable would stop compiling.
- **One generic declaration** (`_ message: some …`). A literal in a generic position takes its default type, `String`, and a `privacy:` segment then fails; the type checker doesn't try `LogMessage`.
- **Two declarations with no tie-breaker.** Ambiguous for messages typed from context, as above.

Known edge: an optional logger passed with a `privacy:` message type-checks against the second declaration and then fails in the expansion (`value of optional type must be unwrapped`), rather than at the macro. The `String` form rejects it at the macro, as before. `Tests/SwiftMoLoggerSugarTests` compiles real `#log` calls of every form on each CI toolchain.
