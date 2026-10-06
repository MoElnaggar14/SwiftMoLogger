# The production playbook: tracing, redaction, flight recorder

> Every iOS engineer has a war story about the day the App Store reviewer found a password in a debug log. Or a JWT in Sentry. Or a credit card in a crash report. The features in this article exist because those days are bad.

This is the article on the features that pay for themselves on the call you don't want to take at 3 AM: **W3C distributed tracing**, **privacy and redaction**, and the **flight recorder**. The code is the 4.0 API: no singletons, one injected `LogEnvironment` (see the [README](../README.md), or [MIGRATION.md](../MIGRATION.md) from 3.x). In the snippets, `logging` is that environment and `logger` is `logging.logger`.

## Distributed tracing: connecting your iOS app to your backend's APM

Your backend team has Datadog. Or Honeycomb. Or OpenTelemetry. They have request waterfalls beautiful enough to frame. Then your iOS app calls their endpoint with no `traceparent` header and the waterfall starts mid-call, like a story missing its first chapter.

W3C Trace Context fixes this. Think of the baggage tag on a suitcase: the same tag follows the bag through every airport, so when it goes missing anyone can trace its whole route. Here the tag is the `traceparent` header, carrying a trace ID and span ID across every service that touches a request. In 4.0 it takes a scope and one line per request:

```swift
let network = NetworkLogger(environment: logging)
let session = URLSession(configuration: .default, delegate: network, delegateQueue: nil)

try await TraceContext.generate().run {
    logger.info("Checkout started")         // carries trace.id / span.id metadata

    var request = URLRequest(url: chargeURL)
    request.addTraceparentHeader()          // traceparent: 00-<traceID>-<childSpanID>-01
    let (data, _) = try await session.data(for: request)
    // …
}
```

Inside `run`, every entry logged by any logger carries `trace.id`, `span.id` and `trace.sampled`, so your iOS logs and the backend spans share one ID.

### The `TraceContext` value type

```swift
public struct TraceContext: Sendable, Hashable, Codable, CustomStringConvertible {
    public let traceID: String   // 32 lowercase hex chars
    public let spanID: String    // 16 lowercase hex chars
    public let sampled: Bool

    public init?(traceID: String, spanID: String, sampled: Bool = true)
    public static func generate(sampled: Bool = true) -> TraceContext
    public func childSpan() -> TraceContext
    public static func parse(traceparent: String) -> TraceContext?
    public var traceparent: String   // "00-<traceID>-<spanID>-<flags>"
}
```

The randomness comes from `SecRandomCopyBytes`. In 3.x the initializer enforced the format with `precondition`s, so a malformed ID could crash the app. In 4.0 it's failable: it returns `nil` unless the IDs are 32 and 16 hex characters, and it rejects all-zero IDs, which the W3C spec treats as invalid. `parse(traceparent:)` applies the same checks plus the version and field count.

That matters because trace IDs usually come from outside the app, say a `traceparent` your backend puts in a push payload:

```swift
if let header = userInfo["traceparent"] as? String,
   let upstream = TraceContext.parse(traceparent: header) {
    try await upstream.childSpan().run {
        try await syncOrder()
    }
}
```

Bad input is simply ignored. Nothing traps.

### Task-local propagation

`run` sets two `@TaskLocal`s: `CurrentTrace.current`, which the header helper reads, and `LogContext.current`, the ambient metadata the registry merges into every entry. Task-locals fit because traces are per request, not per process. Children inside `withTaskGroup` inherit the trace, and so does a plain `Task { }` started in the scope; `Task.detached` doesn't. Two concurrent requests never see each other's trace.

### Header injection: now explicit

In 3.x a `URLProtocol` stamped every request for you. 4.0 removed it: the system creates `URLProtocol` instances itself, so they can't receive dependencies. Its replacement, `NetworkLogger`, is a `URLSessionTaskDelegate` that only observes and never changes a request.

So you call `addTraceparentHeader()` yourself. It does nothing outside a trace and never overwrites a header you set. It stamps `childSpan()`, so every outbound call is a *child* of the active trace and one iOS-side trace shows up downstream as a tree. One line in your API client's request builder covers the whole app.

### What it costs

Very little: a 24-byte random read per context, a task-local lookup and a header set per request. The win is at the human end. When someone says "this request failed for user X at 14:22", you paste the trace ID into your APM and see the iOS span, the gateway, the database call and the upstream timeout in one waterfall.

## Privacy: safe defaults, explicit redaction

The day-1 problem with logging is that engineers log too little. The day-100 problem is that they log too much: passwords, tokens, cards, emails. 4.0 attacks this in layers.

### Layer 1: the system log is private in release

The unified log ends up in sysdiagnose archives users send to support. `SystemLogger` now defaults to `privacy: .privateInRelease`: readable while you debug, `<private>` in release builds. To choose differently, replace the default logger in place (same subsystem and category, so same engine ID):

```swift
logging.registry.addEngine(SystemLogger(privacy: .hashed))   // or .public / .private
```

`.hashed` keeps a stable hash, so identical messages can still be correlated.

### Layer 1½: mark the value, not the message

Engine-level privacy hides whole messages. Often only one value is sensitive, so mark that value where you log it, as you would with `os.Logger`:

```swift
logger.info("Signed in \(email, privacy: .private) on \(device)")   // "Signed in <private> on iPhone"
logger.info("Account \(userID, privacy: .private(mask: .hash))")    // "Account <hash:07ee7e07b4b19223>"
logger.notice("Refreshed \(token, privacy: .sensitive)")            // never shown, even in DEBUG
```

The value is replaced before the entry exists, so files, remote shippers and the live tail never see it. `logging.registry.revealsPrivateValues = true` in DEBUG builds shows `.private` values while you debug; `.sensitive` stays hidden. Plain messages are unchanged.

### Layer 2: redaction, where the data leaves

Redaction is opt-in, and it's a decorator: `RedactingLogEngine` wraps any engine and runs the message and every metadata string (recursively) through a `Redactor`. Default rules cover JWTs, Bearer and Basic tokens, AWS and GCP keys, emails, card-shaped numbers, phone numbers, IPv4 addresses and UUIDs. To wrap the default system logger:

```swift
logging.registry.enableRedaction(at: 0)
```

This is the part people get wrong: `enableRedaction(at:)` covers **one** engine, the one at that index. It swaps it atomically via `replaceEngine(id:with:)` (3.0 removed and re-added every engine, dropping logs in between) and is idempotent. Every other engine that persists or ships logs needs its own wrapper:

```swift
let file = try FileLogEngine(fileURL: logsURL)
logging.registry.addEngine(RedactingLogEngine(wrapping: file))

if let sentry = SentryLogEngine(dsn: sentryDSN, release: "1.4.2", environment: "production") {
    logging.registry.addEngine(RedactingLogEngine(wrapping: sentry))
}

// Keep a raw in-memory buffer for in-app debugging.
logging.registry.addEngine(MemoryLogEngine())
```

That's why it's a decorator, not a flag. The day someone says "redact JWTs from what we ship but keep them in the debug console", you move the wrapper. No API surgery. Custom rules go into a `Redactor` you pass along:

```swift
var redactor = Redactor()
try redactor.add(Redactor.Rule(name: "ssn", pattern: #"\d{3}-\d{2}-\d{4}"#, replacement: "[SSN]"))
logging.registry.addEngine(RedactingLogEngine(wrapping: file, redactor: redactor))
```

It's `NSRegularExpression` underneath, so no new dependency. It's a safety net, not a guarantee: review what you log, too.

### Layer 3: the network logger redacts by default

Network logs are where secrets hide best. `NetworkLogger` handles three cases unasked:

- **Headers.** `Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`, `X-Auth-Token` and `Proxy-Authorization` values become `[REDACTED]`.
- **URLs.** With the default `URLRedaction.default`, `user:password@` is dropped and the values of common secret query items (`token`, `code`, `api_key`, `signature`, …) become `REDACTED`, everywhere a URL is written: entries, breadcrumbs, the Hub's waterfall.
- **Errors.** It logs domain, code and message, never `String(describing: error)`: a `URLError`'s `userInfo` holds the full, unredacted failing URL. An earlier 4.0 build did exactly that, leaking the URL the redaction was hiding.

Other policies are one argument:

```swift
let strict = NetworkLogger(environment: logging, urlRedaction: .withoutQuery)   // drop query strings
let raw = NetworkLogger(environment: logging, urlRedaction: .full)              // local debugging only
```

Bodies are the riskiest part of an exchange, so they're off unless you ask. `bodies: .debugOnly(maxBytes:)` captures nothing in a release build; `.always(maxBytes:)` is the explicit opt-in for production. Captured bodies go through the `Redactor`, binary types are skipped, and they stay in the Hub's store, never in log entries.

### Layer 4: what you still have to declare

`SwiftMoLogger` and `SwiftMoLoggerDiagnostics` each ship a `PrivacyInfo.xcprivacy` for the required-reason APIs they use, declaring no tracking and no collected data, because the package sends nothing off the device by itself. Add a remote engine and that changes: declare what you ship in your app's own manifest and App Store privacy details, typically diagnostics and crash data, plus whatever your log messages contain.

## Shipping logs without shipping secrets

The remote engines (`SentryLogEngine`, `DatadogLogEngine`, `LokiLogEngine`, `OTLPLogEngine`, built on `HTTPLogShipper`) batch, retry with backoff and cap their buffer offline. Three notes:

- **`SentryLogEngine(dsn:)` is failable.** A malformed DSN from remote config returns `nil` instead of crashing.
- **Watch your keys.** `DatadogLogEngine(apiKey:service:)` sends that key from every device, and anything compiled into an app can be extracted. Never embed an org-wide secret. To keep keys off the device, point a plain `HTTPLogShipper(configuration: .init(endpoint: yourURL))` at your own backend and forward from there.
- **Wrap shippers in a redactor**, as above. They upload on their own ephemeral `URLSession`, so batches never get logged and shipped again.

Decorators stack. With the `sentry` engine from above (register this instead of the plain wrapper): redact, then group, then rate-limit:

```swift
logging.registry.addEngine(
    RedactingLogEngine(wrapping:
        ErrorGroupingEngine(wrapping:
            RateLimitingLogEngine(wrapping: sentry, permitsPerSecond: 5, burst: 20)))
)
```

Redacting first helps grouping: a scrubbed email reads the same in every message. `ErrorGroupingEngine` fingerprints warnings and above by normalising the message (UUIDs, hex, quoted strings and numbers become placeholders) and forwards only the first `emitThreshold` occurrences of each shape (default 1). It remembers up to `maxGroups` shapes (default 1,000); `snapshot()` returns the counts. `RateLimitingLogEngine` is a token bucket, and `SamplingLogEngine(wrapping:strategy:)` keeps a fraction of entries, uniformly or per level.

### Flush before iOS suspends you

Batching is what makes shipping cheap, and it's also what loses the last batch. iOS can terminate a suspended app without warning, and whatever a shipper or `FileLogEngine` was still holding goes with it. That's usually the batch you wanted, because it leads up to the moment the user gave up.

So `LogEngine` has a `flush()` requirement. It does nothing by default, buffering engines override it to write or send what they hold, and every decorator above forwards it to the engine it wraps. Flush the whole registry when the scene goes to the background:

```swift
.onChange(of: scenePhase) { _, phase in
    if phase == .background { logging.registry.flush() }
}
```

Write a custom engine that buffers? Override `flush()` too. Otherwise the decorators forward to a no-op and the batch is lost anyway.

## Flight recorder: the black box

The flight recorder is the feature I added last because it's been the most useful in my own day job. It addresses the hardest crash report: *the app died and we don't know why*.

```swift
let recorder = FlightRecorder(
    environment: logging,
    window: 120,           // seconds of history kept (the default)
    flushInterval: 5,      // the default
    redactor: Redactor()   // nothing raw reaches the disk
)
recorder.start()

if let session = recorder.crashedSession {
    logger.warning("Recovered crashed session: \(session.entries.count) entries")
    // Upload it, or attach it to a bug report.
}
```

It keeps the last 2 minutes of logs, network events, signpost spans and vitals, plus recent breadcrumbs, in `Caches/SwiftMoLogger/flight-recorder.json`. A "session running" flag in `UserDefaults` is set at start and cleared on a clean `stop()`. `crashedSession` is non-nil only when the previous run never cleared it: almost always a crash, an out-of-memory kill or a watchdog timeout. `start()` captures it before marking the new session running, so it's safe to read afterwards.

Three changes since 3.0 make it fit for production:

- **It writes only when something changed.** 3.0 rewrote the file every 2 seconds even when idle, enough for iOS disk-write warnings. Now the default is 5 seconds and an idle app does no disk I/O.
- **Swipe-aways aren't crashes.** iOS kills suspended apps without warning. On iOS, tvOS and visionOS the recorder flushes on entering the background and marks the session clean, then running again on return. The honest trade-off: a crash *while running in the background* isn't detected either.
- **The redactor covers everything it writes.** Entries, breadcrumbs and network-event errors go through it, and network URLs lose their query strings. The crash file often gets uploaded, so it deserves a shipper's care.

The output is a `Codable` `FlightRecorder.Session`: upload it, attach it to a bug report, or someday scrub through it in the [Diagnostics Hub](03-diagnostics-hub.md). That last one isn't implemented yet, but the data shape is ready.

It pairs well with MetricKit (iOS and macOS). The recorder tells you what the app was doing; `MetricKitCrashReporter(logger:)` logs the crash, hang and resource diagnostics the OS delivers on the next launch, which tell you how it died. On iOS it also logs the daily metric payload (launch time, hang time, peak memory, disk writes), so slow launches show up next to everything else:

```swift
let metricKit = MetricKitCrashReporter(logger: logger)
metricKit.startMonitoring()
```

## What ties them together

Each of these is a small piece of code. They fit because the core abstractions are small: `LogEntry` is a plain value and a `LogEngine` mostly just implements `log(_:)` (plus `flush()` if it buffers), so they compose. Tracing stamps metadata. Redaction rewrites it. Grouping fingerprints messages. The flight recorder snapshots everything. None needed a new architectural concept: each is another engine, another decorator, or another reader of the stores.

4.0 added one rule: nothing is global. Each piece takes the environment or logger it works with, which is also what lets tests run in parallel, each with its own environment.

Good design is the design where the next feature is short to write. The point of the rewrite was to *make the next feature short to write*. Five articles later, I think we got there.

— Mohammed
