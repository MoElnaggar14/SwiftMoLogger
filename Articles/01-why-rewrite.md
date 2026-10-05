# Why I rewrote iOS logging from scratch

> The third logger I shipped this year started, like the others, with a single `print("starting…")`. I'm telling on myself.

There's a peculiar gravity around logging in iOS apps. Every team starts the same way: `print`, then `os.Logger`, then someone reads a blog post and we add SwiftyBeaver, then six months later we add CocoaLumberjack for a destination Beaver doesn't have, then someone wires up a `URLProtocol` to capture network traffic, then we wrap `XCTestObservation` so tests can assert on logs… and we end up with five overlapping abstractions, none of which we own, all of them reached through a global.

SwiftMoLogger is the result of staring at that situation and designing backwards from what a small team actually needs in production. Version 3 got the shape right. Version 4.0 removed the thing I came to regret most: the global itself.

## What's wrong with what we already have

Apple's `os.Logger` is fast, integrates with Console.app, keeps dynamic values private by default, and is the right default. But it has three holes that bite real teams:

1. **It's text, not data.** You get a level, a subsystem, a category and a timestamp. But the **structured payload** isn't there. You can't ask it "give me every entry with `order_id = ord_4291`", because that knowledge dies in the interpolated string.

2. **Single output.** You can't fan one entry out to a file, to Sentry, to an in-app debug console and to your unit tests at the same time. Each consumer needs its own wiring.

3. **No live view inside the app.** TestFlight builds with mysterious bug reports are common. By the time the screenshot reaches you, the logs are long gone.

SwiftyBeaver and CocoaLumberjack solve fan-out, and they've served many apps well. What I missed was different: metadata is an untyped side channel rather than the core of the model, there's no built-in redaction or test assertions, and the usual entry points (`SwiftyBeaver.info`, `DDLogInfo`) are global. That last one mattered more than I expected.

## The design principles

I wrote six rules on the whiteboard. 4.0 is where the last of them finally held.

### 1. No globals: one environment, injected

In 3.x, `SwiftMoLogger.info("hi")` worked the moment you imported the package. That felt like zero ceremony, but the cost was only hidden: tests shared one registry and couldn't run in parallel, frameworks logged into the host app's engines, and nothing in a type's initialiser told you it logged.

So 4.0 has no singletons. You create one `LogEnvironment` at your composition root and inject the narrowest piece each component needs:

```swift
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

Think of the composition root as a building's fuse box: the wiring decisions live in one cupboard, and each room just gets an outlet. `CheckoutService` doesn't know whether its logs reach the system log, a file or Sentry. Starting is still one line, because the registry installs a `SystemLogger` when it's created; there's no `configure(…)` step.

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

Every call materialises a `LogEntry` value carrying level, tag, metadata, source location and thread. Engines receive the whole value; they don't re-parse a string or invent their own context model. When a remote backend wants `order_id` as a separate field, it's already there.

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

This was the most important change from v2. The Hub timeline, the Sentry shipper, the redaction decorator and the test assertions were easy to build because they all consume the same shape.

### 3. Engines are strategies

An engine is anything that implements `log(_ entry: LogEntry)`. The registry doesn't care what happens next: `os_log`, a ring buffer, a JSON-Lines file, an HTTP batch. Decorators like `RedactingLogEngine`, `SamplingLogEngine` and `RateLimitingLogEngine` wrap any engine, the way a surge protector goes between the wall and whatever you plug in.

### 4. Swift 6 strict concurrency, not "thread-safe, trust me"

The library compiles in the Swift 6 language mode with full data-race checking. `LogEntry` and `MoLogger` are `Sendable` values, `LogEngine` requires `Sendable`, and ambient context (`LogContext.with(_:operation:)`) is `@TaskLocal`, so concurrent tasks never trample each other's metadata. Your app can stay in Swift 5 mode.

### 5. Private by default, no surprises in production

v2 had a nasty bug: `SystemLogger`'s `info` and `warn` were wrapped in `#if DEBUG`, so release builds silently dropped them. Now a log call **always** runs unless you filter it (`registry.minimumLevel`). The only debug-gated entry point is `debug(_:)`, and it says so in the name.

The other half is privacy. The unified log ends up in sysdiagnose archives that users send to support, so `SystemLogger` defaults to `.privateInRelease`: readable while you debug, `<private>` in release builds. Anything else is a choice you make out loud:

```swift
logging.registry.addEngine(SystemLogger(privacy: .public))  // replaces the default in place
logging.registry.enableRedaction(at: 0)                      // opt-in PII scrubbing
```

Redaction only covers the engine it wraps, so wrap every engine that persists or ships logs. Targets that use required-reason APIs ship a `PrivacyInfo.xcprivacy`. And initialisers fed by outside input (`TraceContext(traceID:spanID:)`, `SentryLogEngine(dsn:)`, `WebSocketTailEngine(url:)`) return `nil` on bad input instead of crashing.

### 6. Pay only for what you import

The core target has zero dependencies. SwiftUI views, remote shippers, swift-log interop and Swift Macros (which pull in `swift-syntax`) are separate products. A team that just wants structured logging gets just that.

```
SwiftMoLogger              — core: LogEnvironment, MoLogger, engines, redaction
SwiftMoLoggerUI            — SwiftUI console + Diagnostics Hub
SwiftMoLoggerNetwork       — NetworkLogger, an injected URLSession delegate
SwiftMoLoggerRemote        — Sentry / Datadog / Loki shippers
SwiftMoLoggerDiagnostics   — bug reports, vitals, Bonjour live sink
SwiftMoLoggerTesting       — XCTest helpers, recording environments
SwiftMoLoggerSugar         — Swift Macros
SwiftMoLoggerSwiftLog      — swift-log backend
```

## What that buys you

The articles that follow walk through the consequences:

- A **~140 ns hot path** with no engines attached comes from these design choices, not from optimisation passes after the fact ([article 2](02-performance.md)).
- An **in-app Instruments dashboard** is feasible because every signal (logs, network, signposts, vitals) is a `Sendable` value the SwiftUI layer can chart directly ([article 3](03-diagnostics-hub.md)).
- A **CLI that tails every device on your Wi-Fi** is a small `NWBrowser` loop, because the on-device sink ships JSON-Lines `LogEntry` values ([article 4](04-bonjour-and-macros.md)).
- **Distributed tracing, PII redaction and a flight recorder** drop in as engines and decorators because the fan-out architecture already speaks the right vocabulary ([article 5](05-production-playbook.md)).

The goal was a logger I'd want on every team I work with. The way to know if I got there is to install it and never want to switch back. Start with the [README](../README.md).

— Mohammed
