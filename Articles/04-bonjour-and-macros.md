# Zero-config debugging with Bonjour and Swift Macros

> Half of what a senior iOS engineer spends their day on is *not* writing iOS code. It's reading logs, ten devices at a time, on a flaky office Wi-Fi, while someone keeps unplugging the cable.

This article is about two parts of SwiftMoLogger that exist to make that day shorter: a Bonjour-advertised live tail, and a small set of Swift Macros for the call sites. In 4.0 neither touches a global: you build one `LogEnvironment` and inject it (see the [README](../README.md) and [MIGRATION.md](../MIGRATION.md)).

## Bonjour: the cable nobody plugs in

The standard iOS debugging loop is *plug in the device → trust the certificate → reload Xcode → open Console → filter by subsystem*. Each step has failure modes, and each gets tedious three times a day across a fleet of QA devices.

The loop I wanted is: *open Terminal, run one command, see every device's logs immediately*.

Think of it as radio. Each device runs a small station that announces itself on the local network. The Mac runs a scanner that finds every station and tunes in.

### The iOS side

`LiveSink` is a `LogEngine` that opens an `NWListener` and advertises it over Bonjour as `_swiftmologger._tcp`. Its initializer is `LiveSink(port:serviceName:minimumLevel:statusLogger:allowInRelease:)`, and every argument has a default:

```swift
import SwiftMoLogger
import SwiftMoLoggerDiagnostics

func attachLiveTail(to logging: LogEnvironment) {
    #if DEBUG
    let sink = LiveSink(serviceName: "MyApp-iPhone-15", statusLogger: logging.logger)
    do {
        try sink.start()
        logging.registry.addEngine(sink)
    } catch {
        logging.logger.error(error, tag: .debug)
    }
    #endif
}
```

The `serviceName` defaults to the bundle identifier, so ten devices running one app would announce the same name. Picking your own keeps the terminal readable. The `statusLogger` hears "LiveSink ready" or "LiveSink failed".

Each `LogEntry` goes out as one line of JSON: JSON-Lines over TCP, no framing protocol, no handshake beyond Bonjour discovery. A new client first gets a small banner line naming the app. Encoding and sending happen on a background queue, so the call site never waits on the network.

### Info.plist and safety

On iOS, the app must ask before using the local network. Without these keys the listener fails on a real device:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Streams debug logs to the SwiftMoLogger Inspector on your Mac.</string>
<key>NSBonjourServices</key>
<array>
    <string>_swiftmologger._tcp</string>
</array>
```

Back to the radio: this one is a walkie-talkie, not a phone call. `LiveSink` streams every line unencrypted and unauthenticated to anyone who connects. So in 4.0, `start()` does nothing in a non-DEBUG build unless you pass `allowInRelease: true` (meant for internal QA builds on a network you trust). I still wrap the setup in `#if DEBUG` and put the plist keys in the debug configuration only.

### The Mac side

The Inspector is an executable product in the same package, `swiftmologger-inspector`. From a checkout of the repo:

```bash
swift run swiftmologger-inspector
```

It takes no arguments. It uses `NWBrowser` to find every `_swiftmologger._tcp` service and opens an `NWConnection` to each:

```swift
let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
browser.browseResultsChangedHandler = { [weak self] results, _ in
    self?.handle(results: results)   // connect to new services, drop vanished ones
}
```

Each line prints as *timestamp (ISO 8601, UTC), level, device, tag, [thread], message*, coloured by level. Abridged:

```
SwiftMoLogger Inspector — discovering _swiftmologger._tcp on local network…
◉ discovered MyApp-iPhone-15
◉ discovered MyApp-iPad-Pro
● connected MyApp-iPhone-15
…banner from MyApp-iPhone-15: MyApp-iPhone-15
2026-10-05T14:22:01.124Z INFO  MyApp-iPhone-15 [API] [thread] HTTP response 200
2026-10-05T14:22:01.221Z WARN  MyApp-iPad-Pro [Layout] [main] Auto-layout broke 3 constraints
2026-10-05T14:22:01.337Z ERROR MyApp-iPhone-15 [Database] [thread] Migration v4 → v5 timed out
◌ gone MyApp-iPad-Pro
```

Metadata isn't printed, so keep the key fact in the message. No certificates, no cables, no Xcode. The tool is one file of about 150 lines of `Network.framework`, because Apple's APIs are good when you let them be.

## Swift Macros: the call site you don't have to think about

The other half of the loop is *typing log statements*. With an injected logger, the plain API is already good:

```swift
logger.info("user signed in", tag: .api,
            metadata: ["user_id": .string(user.id)])
```

Macros trim that without losing the structure. One rule holds for all three in 4.0: **the dependency is explicit.** There's no global logger for a macro to reach.

### `#log` — source location, captured at the call site

```swift
import SwiftMoLoggerSugar

#log(logger, "user signed in", level: .info, tag: .api)
```

The first argument is any `MoLogger` expression; `level` defaults to `.info`, `tag` to `nil`. The expansion, straight from the macro tests, is what you'd write by hand:

```swift
logger.log(.info, "user signed in", tag: .api, file: #fileID, function: #function, line: #line)
```

Why bother? `#log(` is trivial to grep for and code-mod, Xcode shows the expansion in place, and one short shape is easier to teach. It doesn't take `metadata:`; for that, call `logger.info(…, metadata:)` directly.

### `#measure` — a signpost in one line

```swift
let users = try #measure(signposter, "loadUsers") {
    try repo.all()
}
```

`signposter` is a `Signposter`, typically `logging.signposter` injected into the component. This lowers to `signposter.measure("loadUsers") { try repo.all() }`, which emits an `os_signpost` interval for Instruments, logs one timing entry, and records a span for the Diagnostics Hub.

Honestly, this one saves little: the direct call is as short, and it also takes a `tag:`, which the macro doesn't forward. I keep it because it reads consistently next to `#log`.

### `@AutoLog` — a helper, not magic

```swift
@AutoLog
final class CheckoutService {
    let logger: MoLogger
    init(logger: MoLogger) { self.logger = logger }

    func purchase(_ id: String) throws {
        __autoLog()        // you write this line; the macro doesn't
        // …
    }
}
```

`@AutoLog` adds one member to a type that has at least one method:

```swift
@inline(__always)
fileprivate func __autoLog(_ method: String = #function,
                           file: String = #fileID,
                           line: Int = #line) {
    logger.trace("→ \(method)", tag: .Development.debug, file: file, function: method, line: line)
}
```

Call it first thing in a method and you get a trace entry like `→ purchase(_:)` with the right file and line. It logs through the type's own property, which must be named `logger`.

What it does *not* do: log every method automatically, log exits or thrown errors, or add signposts. The macro also declares a member-attribute role, but that role currently adds nothing. A method without `__autoLog()` stays silent.

That's deliberate. Rewriting function bodies with macros is still an unsettled corner of Swift, and code that rewrites every adopter's methods breaks on some adopter's compiler. A per-method helper you can grep for is the stable middle ground.

### The opt-in cost

Macros need `swift-syntax` at build time, a large dependency that noticeably lengthens clean builds. Forcing that on every adopter would be hostile.

So the macros live in their own product, `SwiftMoLoggerSugar`, which re-exports `SwiftMoLogger`. Teams who want them add:

```swift
.product(name: "SwiftMoLoggerSugar", package: "SwiftMoLogger")
```

Everyone else depends on `SwiftMoLogger` and never builds `swift-syntax`. The supported range is `509.0.0..<605.0.0`, Swift 5.9 through 6.4, wide on purpose so it doesn't clash with other packages in your app.

## What these two pieces share

They both target what I call **dev-experience surface area**. They don't make your code faster, catch new bugs, or add a sink. They make the moments around logging — typing the call, reading output across devices — cheaper.

Dev experience is undervalued in iOS tooling. We accept slow compile cycles, hand-rolled URLSession capture, and ad-hoc breakpoints because that's how it's always been. SwiftMoLogger's bet is that an afternoon saved on device setup, and one fewer hand-typed source location, compound across a team into velocity you can't buy back any other way.

Previous: [Instruments in your app](03-diagnostics-hub.md) · Next: [The production playbook](05-production-playbook.md)

→ See [`LiveSink.swift`](../Sources/SwiftMoLoggerDiagnostics/LiveSink.swift), [`Inspector.swift`](../Sources/SwiftMoLoggerInspector/Inspector.swift) and [`Sources/SwiftMoLoggerMacros/`](../Sources/SwiftMoLoggerMacros) for the implementation.
