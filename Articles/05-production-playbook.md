# The production playbook: tracing, redaction, flight recorder

> Every iOS engineer has a war story about the day the App Store reviewer found a password in a debug log. Or a JWT in Sentry. Or a credit card in a crash report. The features in this article exist because those days are bad.

This is the article on the features that pay for themselves on the call you don't want to take at 3 AM: **W3C distributed tracing**, **privacy and redaction**, and the **flight recorder**. All the code is the 4.0 API: no singletons, one `LogEnvironment` created at your composition root and injected (see the [README](../README.md), or [MIGRATION.md](../MIGRATION.md) if you're coming from 3.x). In the snippets, `logging` is that environment and `logger` is `logging.logger`.

## Distributed tracing: connecting your iOS app to your backend's APM

Your backend team has Datadog. Or Honeycomb. Or OpenTelemetry. They have request waterfalls beautiful enough to frame. Then your iOS app calls their endpoint with no `traceparent` header and the waterfall starts mid-call, like a story missing its first chapter.

W3C Trace Context fixes this. Think of it as the baggage tag on a suitcase: the same tag follows the bag through every airport, so when it goes missing anyone can look up its whole route. The tag here is the `traceparent` header, which carries a trace ID and a span ID across every service that touches a request.

In 4.0 it takes a scope and one line per request:

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

The randomness comes from `SecRandomCopyBytes`. In 3.x the initializer enforced the format with `precondition`s, which meant a malformed ID from a header could crash the app. In 4.0 the initializer is failable: it returns `nil` unless the trace ID is 32 hex characters and the span ID 16, and it also rejects all-zero IDs, which the W3C spec treats as invalid. `parse(traceparent:)` goes through the same checks, plus the version byte and field count.

That matters because trace IDs usually come from outside the app. Say your backend puts a `traceparent` in a push notification payload so you can follow it on device:

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

`run` sets two task-locals: `CurrentTrace.current`, which the header helper reads, and `LogContext.current`, the ambient metadata the registry merges into every entry.

```swift
public enum CurrentTrace {
    @TaskLocal public static var current: TraceContext?
}
```

`@TaskLocal` is the right tool because traces are per request, not per process. Child tasks inherit the value: inside `withTaskGroup`, every child sees the same trace, and so does a plain `Task { }` started in the scope. `Task.detached` does not, by design. Two concurrent requests never see each other's trace.

### Header injection: now explicit

In 3.x a `URLProtocol` stamped every outgoing request for you. 4.0 removed it, because the system creates `URLProtocol` instances itself and they can't receive dependencies. Its replacement, `NetworkLogger`, is a `URLSessionTaskDelegate` that only observes: it never changes a request.

So you add the header yourself:

```swift
public extension URLRequest {
    mutating func addTraceparentHeader() {
        guard value(forHTTPHeaderField: "traceparent") == nil, let trace = CurrentTrace.current else { return }
        setValue(trace.childSpan().traceparent, forHTTPHeaderField: "traceparent")
    }
}
```

It does nothing outside a trace, and it never overwrites a header you set. Note `childSpan()`: every outbound call gets a *child* of the active trace, so one iOS-side trace can span many HTTP calls and still show up as a tree downstream. One line in your API client's request builder covers the whole app.

### What it costs

Very little at runtime: a 24-byte random read when you generate a context, a task-local lookup and a header set per request. The win is at the human end. When someone says "this request failed for user X at 14:22", you paste the trace ID into your APM and see the iOS span, the gateway, the database call and the upstream timeout in one waterfall.

## Privacy: safe defaults, explicit redaction

The day-1 problem with logging is that engineers log too little. The day-100 problem is that they log too much: passwords, tokens, cards, emails. 4.0 attacks this in layers.

### Layer 1: the system log is private in release

The unified log ends up in sysdiagnose archives that users send to support. `SystemLogger` now defaults to `privacy: .privateInRelease`: readable while you debug, `<private>` in release builds. If you really want something else, replace the default logger in place (same subsystem and category, same engine ID):

```swift
logging.registry.addEngine(SystemLogger(privacy: .hashed))   // or .public / .private
```

`.hashed` keeps a stable hash, so identical messages can still be correlated.

### Layer 2: redaction, where the data leaves

Redaction is opt-in, and it's a decorator: `RedactingLogEngine` wraps any engine and runs every message and every string in the metadata (recursively) through a `Redactor`. The default rules cover JWTs, Bearer and Basic tokens, AWS and GCP keys, emails, card-shaped numbers, phone numbers, IPv4 addresses and UUIDs.

To wrap the default system logger in place:

```swift
logging.registry.enableRedaction(at: 0)
```

This is the part people get wrong: `enableRedaction(at:)` covers **one** engine, the one at that index. It swaps it atomically with `replaceEngine(id:with:)` (in 3.0 it removed and re-added every engine, and dropped logs in between), and it's idempotent. Every other engine that persists or ships logs needs its own wrapper:

```swift
let file = try FileLogEngine(fileURL: logsURL)
logging.registry.addEngine(RedactingLogEngine(wrapping: file))

if let sentry = SentryLogEngine(dsn: sentryDSN, release: "1.4.2", environment: "production") {
    logging.registry.addEngine(RedactingLogEngine(wrapping: sentry))
}

// Keep a raw in-memory buffer for in-app debugging.
logging.registry.addEngine(MemoryLogEngine())
```

That's why it's a decorator and not a flag. The day someone says "redact JWTs from what we ship but keep them in the debug console", you move the wrapper. No API surgery.

Custom rules go into a `Redactor` you pass along:

```swift
var redactor = Redactor()
try redactor.add(Redactor.Rule(name: "ssn", pattern: #"\d{3}-\d{2}-\d{4}"#, replacement: "[SSN]"))
logging.registry.addEngine(RedactingLogEngine(wrapping: file, redactor: redactor))
```

The engine is `NSRegularExpression`, so no new dependency. It's a regex safety net, not a guarantee: review what you log, too.

### Layer 3: the network logger redacts by default

Network logs are where secrets hide best. `NetworkLogger` handles three of them without being asked:

- **Headers.** `Authorization`, `Cookie`, `Set-Cookie`, `X-API-Key`, `X-Auth-Token` and `Proxy-Authorization` values become `[REDACTED]`.
- **URLs.** With the default `URLRedaction.default`, `user:password@` is dropped and the values of common secret query items (`token`, `code`, `api_key`, `signature`, `X-Amz-Signature`, …) become `REDACTED`. This applies everywhere a URL is written: entries, breadcrumbs and the Hub's waterfall.
- **Errors.** It logs a `URLError` as domain, code and message, never `String(describing:)`. That string includes the error's `userInfo`, which holds the full, unredacted failing URL. An earlier 4.0 build did exactly that, leaking the very URL the redaction was hiding.

Stricter or looser policies are one argument:

```swift
NetworkLogger(environment: logging, urlRedaction: .withoutQuery)   // drop query strings entirely
NetworkLogger(environment: logging, urlRedaction: .full)           // local debugging only
```

### Layer 4: what you still have to declare

`SwiftMoLogger` and `SwiftMoLoggerDiagnostics` each ship a `PrivacyInfo.xcprivacy` for the required-reason APIs they use, declaring no tracking and no collected data. That's true because the package never sends anything off the device by itself. The moment you add a remote engine, that changes: declare what you ship in your app's own manifest and App Store privacy details, typically diagnostics and crash data, plus anything your log messages contain.

## Shipping logs without shipping secrets

The remote engines (`SentryLogEngine`, `DatadogLogEngine`, `LokiLogEngine`, all built on `HTTPLogShipper`) batch, debounce, retry with backoff and cap their buffer when offline. Three production notes:

- **`SentryLogEngine(dsn:)` is failable.** A malformed DSN from remote config returns `nil` instead of crashing.
- **Watch your keys.** `DatadogLogEngine(apiKey:service:)` sends whatever key you give it in a header from every device. Anything compiled into an app can be extracted, so never embed an org-wide secret. If you need to keep keys off the device, point a plain `HTTPLogShipper(configuration: .init(endpoint: yourURL))` at your own backend and forward from there.
- **Wrap shippers in a redactor**, as above. Shippers use their own ephemeral `URLSession`, so their uploads never get logged and shipped again.

For noisy sinks, the decorators stack. Using the `sentry` engine from above, the order here is redact, then group, then rate-limit:

```swift
logging.registry.addEngine(
    RedactingLogEngine(wrapping:
        ErrorGroupingEngine(wrapping:
            RateLimitingLogEngine(wrapping: sentry, permitsPerSecond: 5, burst: 20)))
)
```

Redacting first also helps grouping, because a scrubbed email reads the same in every message. `ErrorGroupingEngine` fingerprints warnings and above by normalising the message (UUIDs, hex blobs, quoted strings and numbers become placeholders) and forwards only the first `emitThreshold` occurrences of each shape, default 1. It remembers at most `maxGroups` shapes (default 1,000) and `snapshot()` returns the counts. `RateLimitingLogEngine` is a token bucket; `SamplingLogEngine(wrapping:strategy:)` drops a fraction of entries, uniformly or per level, for the chatty sinks.

## Flight recorder: the black box

The flight recorder is the feature I added last because it's the one that's been most useful in my own day job. It addresses the hardest category of crash report: *the app died and we don't know why*.

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

It keeps the last 2 minutes of logs, network events, signpost spans and vitals, plus recent breadcrumbs, and writes them to `Caches/SwiftMoLogger/flight-recorder.json`. It sets a "session running" flag in `UserDefaults` at start and clears it on a clean `stop()`. `crashedSession` is non-nil only when the previous run never cleared that flag, which is almost always a crash, an out-of-memory kill or a watchdog timeout. `start()` captures it before marking the new session as running, so it's safe to read any time afterwards.

Three fixes since 3.0 make it fit for production:

- **It writes only when something changed.** 3.0 rewrote the file every 2 seconds even when idle, enough for iOS disk-write warnings. Now the default interval is 5 seconds and an idle app costs no disk I/O.
- **Swipe-aways aren't crashes.** iOS kills suspended apps without warning. On iOS, tvOS and visionOS the recorder flushes when the app enters the background and marks the session clean, then marks it running again on return. The honest trade-off: a crash *while running in the background* isn't detected either.
- **The redactor covers everything it writes.** Entries, breadcrumbs and network-event errors go through it, and network URLs lose their query strings. The crash file sits on the device and often gets uploaded, so it deserves the same care as a shipper.

The output is a `Codable` `FlightRecorder.Session`, so you can upload it, attach it to a `BugReporter` report, or someday load it into the [Diagnostics Hub](03-diagnostics-hub.md) and scrub through the final minutes. That last one isn't implemented yet, but the data shape is ready.

It pairs well with MetricKit (iOS and macOS). The recorder tells you what the app was doing; `MetricKitCrashReporter(logger:)` logs the crash and hang diagnostics the OS delivers on the next launch, which tell you how it died:

```swift
let metricKit = MetricKitCrashReporter(logger: logger)
metricKit.startMonitoring()
```

## What ties them together

Each of these is a small piece of code. They fit because the core abstractions are small: `LogEntry` is a plain value, `LogEngine` is a three-member protocol, and the breadcrumb and event stores are simple ring buffers. Small pieces compose. Tracing stamps metadata. Redaction rewrites it. Grouping fingerprints messages. The flight recorder snapshots everything. None of them needed a new architectural concept: each is another engine, another decorator, or another reader of the stores.

4.0 added one thing to that list: nothing is global. The recorder, the network logger and the bug reporter take the environment they work with, and engines are just values you construct and register. That's also what lets tests run in parallel, each with its own environment.

Good design is the design where the next feature is short to write. The point of the rewrite was to *make the next feature short to write*. Five articles later, I think we got there.

— Mohammed
