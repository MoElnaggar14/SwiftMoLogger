# The production playbook: tracing, redaction, flight recorder

> Every iOS engineer has a war story about the day the App Store reviewer found a password in a debug log. Or a JWT in Sentry. Or a credit card in a crash report. The features in this article exist because those days are bad.

This is the article on the v3 features that pay for themselves on the call you don't want to take at 3 AM: **W3C distributed tracing**, **automatic PII redaction**, and the **flight recorder**.

## Distributed tracing: connecting your iOS app to your backend's APM

Your backend team has Datadog. Or Honeycomb. Or OpenTelemetry. They have request waterfalls beautiful enough to frame. Then your iOS app pings their endpoint with no `traceparent` header and the waterfall starts mid-call, like a story missing its first chapter.

W3C Trace Context fixes this. It's two HTTP headers (`traceparent` and the optional `tracestate`) that propagate a trace ID and span ID across every service that touches a request. v3 generates and propagates them with two lines of code:

```swift
SwiftMoLogger.withTrace {
    try await api.fetchProfile()    // outgoing request carries traceparent: 00-<traceID>-<spanID>-01
}
```

The implementation is small but the design choices are worth talking about.

### The `TraceContext` value type

```swift
public struct TraceContext: Sendable, Hashable, Codable {
    public let traceID: String   // 32 lowercase hex chars
    public let spanID: String    // 16 lowercase hex chars
    public let sampled: Bool

    public static func generate(sampled: Bool = true) -> TraceContext { … }
    public func childSpan() -> TraceContext { … }
    public static func parse(traceparent: String) -> TraceContext? { … }
    public var traceparent: String { "00-\(traceID)-\(spanID)-\(flags)" }
}
```

The randomness comes from `SecRandomCopyBytes`. The W3C spec requires lowercase hex; we enforce that with `precondition`s. `parse(_:)` validates the version byte and field lengths so a malformed inbound header doesn't propagate downstream.

### Task-local propagation

The active trace lives in a `@TaskLocal`:

```swift
public enum CurrentTrace {
    @TaskLocal public static var current: TraceContext?
}
```

`@TaskLocal` is the right tool because traces are per-request, not per-process, and Swift Concurrency child tasks inherit them automatically. When you write `await withTaskGroup { … }`, every child task sees the same trace context.

### Header injection in the network layer

The `NetworkLoggingProtocol` (the `URLProtocol` that auto-captures `URLSession` requests) reads `CurrentTrace.current` and stamps every outgoing request:

```swift
if mutable.value(forHTTPHeaderField: "traceparent") == nil,
   let context = CurrentTrace.current {
    mutable.setValue(context.childSpan().traceparent, forHTTPHeaderField: "traceparent")
}
```

Note `childSpan()`: every outbound HTTP call gets a *child* of the active trace, so a single iOS-side trace can span many HTTP calls and still reconstruct as a tree downstream.

### What it costs

Effectively nothing at runtime — a 16-byte random read on trace creation, a `TaskLocal` lookup per request (constant time), a header set. The win is at the human end: when an engineer says "this request failed for user X at 14:22", they paste the trace ID into Datadog and see the iOS span, the API gateway, the database call, and the upstream timeout in one waterfall.

## PII redaction: the safety net you should have

The day-1 problem with logging is that engineers log too little. The day-100 problem is that engineers log too much — passwords, tokens, credit cards, emails, addresses. The fix is mechanical, not behavioural: every log line passes through a regex-based scrubber before it leaves the process.

```swift
SwiftMoLogger.enableRedaction()
```

That single call wraps the default `SystemLogger` in a `RedactingLogEngine`. The default `Redactor` ships with rules for:

| Rule | Pattern |
|---|---|
| `jwt` | `eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+` |
| `bearer` | Trailing token after `Bearer ` |
| `basic_auth` | Base64 blob after `Basic ` |
| `aws_key` | `AKIA[0-9A-Z]{16}` |
| `gcp_key` | `AIza[0-9A-Za-z\-_]{35}` |
| `email` | RFC-ish email shape |
| `credit_card` | 13–16 digit groups with spacing |
| `phone` | International phone shape |
| `ipv4` | Dotted quad |
| `uuid` | RFC 4122 v4 shape |

The decorator walks `LogEntry.metadata` recursively too, so structured metadata can't bypass it by hiding the secret in a sub-dictionary.

### Why a decorator, not a flag

The pattern matters. `RedactingLogEngine` wraps any `LogEngine`. You can install it once globally:

```swift
SwiftMoLogger.enableRedaction()       // wraps the default SystemLogger
```

…or selectively, only on the sinks that leave the device:

```swift
SwiftMoLogger.addEngine(RedactingLogEngine(wrapping: sentryShipper))
SwiftMoLogger.addEngine(RedactingLogEngine(wrapping: fileEngine))
// Keep the MemoryLogEngine raw for in-app debugging
SwiftMoLogger.addEngine(MemoryLogEngine())
```

This is the design that ages well. The day someone says "redact JWTs from network logs but keep them in the debug console", you adjust where the decorator sits — no API surgery.

### Custom rules

Custom rules are a one-liner:

```swift
var redactor = Redactor()
try redactor.add(Redactor.Rule(
    name: "ssn",
    pattern: #"\d{3}-\d{2}-\d{4}"#,
    replacement: "[SSN]"
))
SwiftMoLogger.addEngine(RedactingLogEngine(wrapping: existingEngine, redactor: redactor))
```

The regex engine is `NSRegularExpression`, which is Foundation. No new dependency. Performance is comparable to a single pass per log line — measurable but not meaningful when the line is going to a file or the network anyway.

## Error grouping: 1 000 occurrences, one card

Production logs are *noisy*. A flaky retry loop emits "DB connection refused" 50 times a second. A bad migration spams "user_id <uuid> failed" with a fresh UUID every call. The naïve handling — fan everything out, every time — turns Sentry into useless white noise.

`ErrorGroupingEngine` is a decorator that fingerprints inbound entries and forwards only the first `N` occurrences of each unique shape:

```swift
SwiftMoLogger.addEngine(ErrorGroupingEngine(
    wrapping: sentryShipper,
    fingerprintMinLevel: .warning,
    emitThreshold: 1
))
```

The fingerprint is computed by normalising the message — UUIDs to `<uuid>`, hex blobs to `<hex>`, quoted strings to `"…"`, digit runs to `#` — then SHA-256 of the result. Different orders of the same error collapse to the same fingerprint. Genuinely different errors don't.

A `snapshot()` call gives you the `ErrorGroup` records (fingerprint, exemplar, first seen, last seen, count) — handy when you want to ship a periodic summary instead of every occurrence.

## Flight recorder: the black box

The flight recorder is the feature I added last because it's the one that's been most useful in my own day job. It addresses a category of crash that's nearly impossible to diagnose otherwise: *the app died and we don't know why*.

```swift
let recorder = FlightRecorder(window: 120, flushInterval: 2)
recorder.start()
```

It persists a rolling 2-minute window of every signal — logs, breadcrumbs, network events, signpost spans, vitals — to `Caches/SwiftMoLogger/flight-recorder.json` every 2 seconds. It also writes a `UserDefaults` flag at start (`alive = true`) and clears it on clean stop.

On next launch:

```swift
if let session = FlightRecorder.recoverLastSession() {
    SwiftMoLogger.warn("Recovered crashed session: \(session.entries.count) entries")
    uploader.attach(session)
}
```

`recoverLastSession()` returns non-nil **only** if the `alive` flag is still set from the previous run — meaning the process died without a clean `stop()`. That's almost always a crash, an OOM kill, or a watchdog timeout.

The 2-second flush is the right tradeoff: 2 seconds of lost context is acceptable; 200 ms of flush every-tick is not. The fixed-capacity ring buffers keep memory bounded, and the JSON encoder runs on a private queue so the write never blocks the main thread.

The output is just a `Codable` `FlightRecorder.Session`, so you can:

- Upload it to your backend for triage,
- Ship it as part of a `BugReporter` zip,
- Or — for the article-3 hook — load it into the Diagnostics Hub and scrub through the final minutes of the previous run.

The last one isn't quite implemented yet but the data shape is right. When it lands, the on-device debugging story is complete: see the live state, scrub through the recent past, replay the moment of death.

## What ties them together

Each of these is a small piece of code. The reason they fit is that v3's core abstractions (`LogEntry`, `LogEngine`, `BreadcrumbStore`, the event stores) are flat value types with no behaviour, so they compose. Tracing stamps metadata. Redaction rewrites metadata. Grouping fingerprints messages. Flight recorder snapshots everything. None of them needed a new architectural concept — they're all "another engine" or "another decorator" or "another reader of the stores".

Good design is the design where the next feature is short to write. The point of the rewrite was to *make the next feature short to write*. Five articles later, I think we got there.

— Mohammed
