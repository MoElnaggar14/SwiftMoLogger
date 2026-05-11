# Why I rewrote iOS logging from scratch

> The third logger I shipped this year started, like the others, with a single `print("starting…")`. I'm telling on myself.

There's a peculiar gravity around logging in iOS apps. Every team starts the same way: `print`, then `os.Logger`, then someone reads a blog post and we add SwiftyBeaver, then six months later we add CocoaLumberjack because Beaver doesn't ship to Sentry, then someone wires up a `URLProtocol` to capture network traffic, then we wrap `XCTestObservation` so tests can assert on logs… and we end up with five overlapping abstractions, none of which we own.

SwiftMoLogger v3 is the result of staring at that situation and deciding to design backwards from what a small team actually needs in production.

## What's wrong with what we already have

Apple's `os.Logger` is fast, integrates with `Console.app`, and is the right default. But it has three holes that bite real teams:

1. **It's string-only.** A log line is a `String`. The level, the category, the timestamp — all there. But the **structured payload** isn't. You cannot ask `os.Logger` "give me every entry with `order_id = ord_4291`", because that knowledge dies in the format string.

2. **Single output.** You can't fan a log entry out to a file, to Sentry, to an in-app debug console, and to your unit tests simultaneously. Each consumer needs its own wiring.

3. **No live view inside the app.** TestFlight builds with mysterious bug reports are common. By the time the screenshot reaches you, the logs are long gone.

SwiftyBeaver / CocoaLumberjack address the fan-out problem but introduce others: heavier hot path (microseconds, not nanoseconds), inconsistent metadata models, no first-class Swift Concurrency, no PII redaction, no `XCTAssertLogged`. And neither integrates with `os_signpost` for Instruments.

## The design principles

When I sketched v3, I wrote four rules on the whiteboard and refused to break any of them.

### 1. Zero ceremony

`SwiftMoLogger.info("hi")` works the moment you `import`. No `configure(…)` step, no protocol you must conform to, no singleton you must initialise in `AppDelegate`. The default `SystemLogger` is installed at registry construction. If a developer can't get started in 30 seconds, they'll keep using `print`.

### 2. Structured all the way down

Every call materialises a `LogEntry` value type carrying level, tag, metadata, source location, and thread. Engines receive the whole value; they don't re-parse a string and they don't need to invent their own context model. When a remote backend wants `order_id` as a separate field, the `LogEntry.metadata` is already there.

```swift
public struct LogEntry: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let message: String
    public let tag: LogTag?
    public let metadata: LogMetadata
    public let source: SourceLocation
    public let threadName: String
}
```

This is the single most important change vs. v2. Every downstream feature — the Diagnostics Hub timeline, the Sentry shipper, the redaction decorator, the test assertions — was easy to build because they all consume the same shape.

### 3. No surprises in production

The previous version of this very package had a critical bug: `SystemLogger.info` and `warn` were wrapped in `#if DEBUG`. In release builds they were no-ops. Customers' production logs were *silently lost* because nobody had spelt out the contract.

The new contract: a log call **always** runs unless you explicitly filter it. The only debug-gated entry point is `debug(_:)` and it says so in the name. Filtering is opt-in via `SwiftMoLogger.minimumLevel`.

### 4. Pay only for what you import

The core target ships zero dependencies and the smallest possible API surface. SwiftUI views? Separate product. Sentry shipping? Separate product. Swift Macros (which pull `swift-syntax`)? Separate product. A team that just wants structured logging gets just structured logging.

```
SwiftMoLogger              — core, always
SwiftMoLoggerUI            — SwiftUI console + Diagnostics Hub
SwiftMoLoggerNetwork       — URLSession auto-capture
SwiftMoLoggerRemote        — Sentry / Datadog / Loki shippers
SwiftMoLoggerDiagnostics   — bug reports, vitals, Bonjour live sink
SwiftMoLoggerTesting       — XCTest helpers
SwiftMoLoggerSugar         — Swift Macros wrapper
```

## What that buys you

The article series that follows this one walks through the consequences:

- A **~140 ns hot path** comes from these design choices, not from optimisation passes after the fact (article 2).
- An **in-app Instruments dashboard** is feasible because every signal — logs, network, signposts, vitals — is a `Sendable` value type that the SwiftUI layer can chart directly (article 3).
- A **CLI that tails every device on your Wi-Fi** is twenty lines of `NWBrowser` because the on-device sink ships JSON-Lines `LogEntry` values (article 4).
- **Distributed tracing, PII redaction, and a flight recorder** drop in as decorators because the fan-out architecture already speaks the right vocabulary (article 5).

The goal was a logger I'd want on every team I work with. The way to know if I got there is to install it and never want to switch back.

— Mohammed
