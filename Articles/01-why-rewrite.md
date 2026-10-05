# Why I rewrote iOS logging from scratch

> The third logger I shipped this year started, like the others, with a single `print("starting…")`. I'm telling on myself.

There's a peculiar gravity around logging in iOS apps. Every team starts the same way: `print`, then `os.Logger`, then someone reads a blog post and we add SwiftyBeaver, then six months later we add CocoaLumberjack for a destination Beaver doesn't have, then someone wires up a `URLProtocol` to capture network traffic, then we wrap `XCTestObservation` so tests can assert on logs… and we end up with five overlapping abstractions, none of which we own, all reached through globals.

SwiftMoLogger is what I got by designing backwards from what a small team needs in production. Version 3 got the shape right. Version 4.0 removed what I came to regret most: the global itself.

## What's wrong with what we already have

Apple's `os.Logger` is fast, integrates with Console.app, keeps dynamic values private by default, and is the right default. But it has three holes:

1. **It's text, not data.** You get a level, subsystem, category and timestamp, but no **structured payload**. You can't ask for "every entry with `order_id = ord_4291`", because that knowledge dies in the interpolated string.

2. **Single output.** You can't fan one entry out to a file, Sentry, an in-app console and your unit tests at once.

3. **No live view inside the app.** By the time a TestFlight bug report reaches you, the logs are long gone.

SwiftyBeaver and CocoaLumberjack solve fan-out, and they've served many apps well. What I missed was different: metadata is an untyped side channel rather than the core of the model, there's no built-in redaction or test assertions, and the usual entry points (`SwiftyBeaver.info`, `DDLogInfo`) are global. That last one mattered more than I expected.

## The design principles

I wrote six rules on the whiteboard. 4.0 is where the last of them finally held.

### 1. No globals: one environment, injected

In 3.x, `SwiftMoLogger.info("hi")` just worked. The cost was hidden: tests shared one registry and couldn't run in parallel, frameworks logged into the host app's engines, and no initialiser told you a type logged.

4.0 has no singletons. You create one `LogEnvironment` at your composition root and inject the narrowest piece each component needs:

```swift
import SwiftUI
import SwiftMoLogger

@main
struct ShopApp: App {
    private let logging = LogEnvironment()   // registry, logger, stream, stores

    var body: some Scene {
        WindowGroup {
            RootView(checkout: CheckoutService(log: logging.logger))
        }
    }
}

final class CheckoutService {
    private let log: MoLogger
    init(log: MoLogger) { self.log = log.with(tag: .business) }

    func pay(orderID: String) {
        log.info("Paying", metadata: ["order_id": .string(orderID)])
    }
}
```

Think of the composition root as a building's fuse box: the wiring lives in one cupboard, and each room just gets an outlet. `CheckoutService` doesn't know whether its logs reach the system log, a file or Sentry. Starting is still one line; the registry installs a `SystemLogger` by default.

The payoff is in tests. Each test owns its environment, so suites run isolated and in parallel:

```swift
import XCTest
import SwiftMoLogger
import SwiftMoLoggerTesting

final class CheckoutTests: XCTestCase {
    func testPaymentIsLogged() {
        let (logging, logs) = LogEnvironment.recording()
        CheckoutService(log: logging.logger).pay(orderID: "42")
        XCTAssertLogged(.info, contains: "Paying", tag: .business, in: logs)
    }
}
```

The upgrade from 3.x is mechanical; [MIGRATION.md](../MIGRATION.md) maps every old call.

### 2. Structured all the way down

Every call materialises a `LogEntry` value. Engines receive the whole thing; they don't re-parse a string or invent their own context model. When a backend wants `order_id` as a separate field, it's already there.

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

This was the most important change from v2: the Hub, the Sentry shipper, redaction and the test assertions all consume the same shape.

### 3. Engines are strategies

An engine is anything that implements `log(_ entry: LogEntry)`. The registry doesn't care what happens next: `os_log`, a ring buffer, a JSON-Lines file, an HTTP batch. Decorators like `RedactingLogEngine`, `SamplingLogEngine` and `RateLimitingLogEngine` wrap any engine, the way a surge protector goes between the wall and whatever you plug in.

### 4. Swift 6 strict concurrency, not "thread-safe, trust me"

The library compiles in Swift 6 language mode with full data-race checking. `LogEntry` and `MoLogger` are `Sendable` values, engines must be `Sendable`, and ambient context (`LogContext.with(_:operation:)`) is `@TaskLocal`, so concurrent tasks can't trample each other's metadata. Your app can stay in Swift 5 mode.

### 5. Private by default, no surprises in production

v2 wrapped `SystemLogger`'s `info` and `warn` in `#if DEBUG`, so release builds silently dropped them. Now a call **always** runs unless you filter it (`registry.minimumLevel`); only `debug(_:)` is debug-gated, and it says so.

The unified log ends up in sysdiagnose archives users send to support, so `SystemLogger` defaults to `.privateInRelease`: readable while you debug, `<private>` in release builds. Anything else is a choice you make out loud:

```swift
logging.registry.addEngine(SystemLogger(privacy: .public))  // replaces the default in place
logging.registry.enableRedaction(at: 0)                      // opt-in PII scrubbing
```

Redaction covers only the engine it wraps, so wrap every engine that persists or ships logs. Targets using required-reason APIs ship a `PrivacyInfo.xcprivacy`, and initialisers fed by outside input (`TraceContext(traceID:spanID:)`, `SentryLogEngine(dsn:)`, `WebSocketTailEngine(url:)`) return `nil` on bad input instead of crashing.

### 6. Pay only for what you import

The core target has zero dependencies. Everything else is a separate product, so a team that just wants structured logging gets just that.

```
SwiftMoLogger              — core, always
SwiftMoLoggerUI            — SwiftUI console + Diagnostics Hub
SwiftMoLoggerNetwork       — injected URLSession delegate
SwiftMoLoggerRemote        — Sentry / Datadog / Loki shippers
SwiftMoLoggerDiagnostics   — bug reports, vitals, Bonjour live sink
SwiftMoLoggerTesting       — XCTest helpers
SwiftMoLoggerSugar         — Swift Macros (pulls swift-syntax)
SwiftMoLoggerSwiftLog      — swift-log backend
```

## What that buys you

The rest of the series walks through the consequences:

- A **~140 ns hot path** (no engines attached) comes from these choices, not from later optimisation passes ([article 2](02-performance.md)).
- An **in-app Instruments dashboard** works because every signal is a `Sendable` value SwiftUI can chart directly ([article 3](03-diagnostics-hub.md)).
- A **CLI that tails every device on your Wi-Fi** is a small `NWBrowser` loop, because the on-device sink ships JSON-Lines `LogEntry` values ([article 4](04-bonjour-and-macros.md)).
- **Distributed tracing, PII redaction and a flight recorder** drop in because the fan-out architecture already speaks the right vocabulary ([article 5](05-production-playbook.md)).

The goal was a logger I'd want on every team I work with. The test is installing it and never wanting to switch back. Start with the [README](../README.md).

— Mohammed
