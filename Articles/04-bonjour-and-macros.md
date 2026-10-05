# Zero-config debugging with Bonjour and Swift Macros

> Half of what a senior iOS engineer spends their day on is *not* writing iOS code. It's reading logs, ten devices at a time, on a flaky office Wi-Fi, while someone keeps unplugging the cable.

This article is about two parts of SwiftMoLogger that exist to make that day shorter: a Bonjour-advertised live tail, and a small set of Swift Macros that make the call sites painless. Both changed shape in 4.0, when the library dropped every singleton. You build one `LogEnvironment` at your composition root and inject it (see the [README](../README.md) and [MIGRATION.md](../MIGRATION.md)). Nothing in this article reaches for a global.

## Bonjour: the cable nobody plugs in

The standard iOS debugging loop is *plug in the device → trust the certificate → reload Xcode → open Console → filter by subsystem*. Each step has failure modes. Each step gets tedious when you do it three times a day across a fleet of QA devices.

The loop I wanted is: *open Terminal, run one command, see every device's logs immediately*.

Think of it as a radio. Each device runs a small station that announces itself on the local network. The Mac runs a scanner that finds every station and tunes in. Nobody has to know a frequency in advance.

### The iOS side

On the device, `LiveSink` is a `LogEngine` that opens an `NWListener` and advertises it over Bonjour as `_swiftmologger._tcp`. In 4.0 it takes its collaborators in the initializer:

```swift
public init(
    port: NWEndpoint.Port = .any,
    serviceName: String? = nil,       // defaults to the bundle identifier
    minimumLevel: LogLevel = .trace,
    statusLogger: MoLogger? = nil,    // receives "LiveSink ready" / "LiveSink failed"
    allowInRelease: Bool = false
)
```

Wiring it up is three lines inside your composition root:

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

I pass a `serviceName` because the default is the bundle identifier, and ten devices running the same app would all announce the same name. Bonjour resolves the clash, but a name you chose is easier to read in the terminal.

Each `LogEntry` goes out as one line of JSON, followed by a newline. That's JSON-Lines over TCP: no framing protocol, no handshake beyond Bonjour discovery. The first line a new client gets is a small banner (`"service": "SwiftMoLogger.LiveSink"`, the app name, a start time), so the Mac knows what it's talking to. Encoding and sending happen on a background utility queue, so the call site never waits on the network.

### Info.plist: two keys, or nothing happens

Since iOS 14, an app must ask before it uses the local network. Without these two keys the listener fails on a real device:

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>Streams debug logs to the SwiftMoLogger Inspector on your Mac.</string>
<key>NSBonjourServices</key>
<array>
    <string>_swiftmologger._tcp</string>
</array>
```

Add them to the Info.plist of your debug configuration only. There's no reason for a release build to ask your users about the local network.

### Keep it debug-only

Back to the radio: it's a walkie-talkie, not a phone call. Anyone on the same channel hears everything. `LiveSink` streams every log line unencrypted and unauthenticated to whoever connects on the network.

So 4.0 makes the safe choice the default. `start()` does nothing in a non-DEBUG build unless you pass `allowInRelease: true`, and it tells your `statusLogger` why. That flag exists for internal QA builds on a network you trust. I'd still keep the `#if DEBUG` around the setup, as above, so the code isn't even in the binary you ship.

### The Mac side

The Inspector is an executable product in the same package, called `swiftmologger-inspector`. From a checkout of the repo, on your Mac:

```bash
swift run swiftmologger-inspector
```

It takes no arguments. It uses `NWBrowser` to find every device advertising `_swiftmologger._tcp` and opens an `NWConnection` to each one:

```swift
let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
browser.browseResultsChangedHandler = { [weak self] results, _ in
    self?.handle(results: results)   // connect to new services, drop vanished ones
}
```

Each incoming line is decoded and printed as *timestamp, level, device, tag, [thread], message*, with ANSI colour by level. The timestamp is the entry's own ISO 8601 time, in UTC. A session looks like this (abridged):

```
SwiftMoLogger Inspector — discovering _swiftmologger._tcp on local network…
◉ discovered MyApp-iPhone-15
◉ discovered MyApp-iPad-Pro
● connected MyApp-iPhone-15
…banner from MyApp-iPhone-15: MyApp-iPhone-15
● connected MyApp-iPad-Pro
…banner from MyApp-iPad-Pro: MyApp-iPad-Pro
2026-10-05T14:22:01.124Z INFO  MyApp-iPhone-15 [API] [thread] HTTP response 200
2026-10-05T14:22:01.221Z WARN  MyApp-iPad-Pro [Layout] [main] Auto-layout broke 3 constraints
2026-10-05T14:22:01.337Z ERROR MyApp-iPhone-15 [Database] [thread] Migration v4 → v5 timed out
◌ gone MyApp-iPad-Pro
```

It prints the message only, not the metadata, so keep the important bit in the message text. No certificates, no cables, no Xcode. The whole tool is one file of about 150 lines of `Network.framework`, because Apple's APIs are good when you let them be.

## Swift Macros: the call site you don't have to think about

The other half of the daily loop is *typing log statements*. With an injected logger, the plain API is already good:

```swift
logger.info("user signed in", tag: .api,
            metadata: ["user_id": .string(user.id)])
```

But that's still a lot of structure for a `print("user signed in")` replacement. Macros let me trim it without losing what makes the structured call valuable.

One rule held for all three macros in 4.0: **the dependency is always explicit.** A macro can't conjure a logger out of thin air any more, because there's no global one to conjure.

### `#log` — source location, captured at the call site

```swift
import SwiftMoLoggerSugar

final class SessionService {
    private let logger: MoLogger
    init(logger: MoLogger) { self.logger = logger }

    func signIn() {
        #log(logger, "user signed in", level: .info, tag: .api)
    }
}
```

The first argument is any `MoLogger` expression. `level` defaults to `.info` and `tag` to `nil`. The expansion is exactly what you'd write by hand:

```swift
logger.log(.info, "user signed in", tag: .api, file: #fileID, function: #function, line: #line)
```

That line is straight from the macro's test suite. Because the message lands in `MoLogger.log`'s `@autoclosure` parameter, it's only built if the level passes the registry's minimum.

Why bother when you could write it yourself? Because `#log(` is trivial to grep for and to code-mod, Xcode shows the expansion in place, and it's easier to teach a new contributor one short shape than the full structured call. The macro doesn't take `metadata:`; when you need metadata, use `logger.info(…, metadata:)` directly.

### `#measure` — a signpost in one line

```swift
import SwiftMoLoggerSugar

final class UserListModel {
    private let signposter: Signposter      // e.g. logging.signposter
    private let repo: UserRepository        // your own type

    init(signposter: Signposter, repo: UserRepository) {
        self.signposter = signposter
        self.repo = repo
    }

    func load() throws -> [User] {
        try #measure(signposter, "loadUsers") {
            try repo.all()
        }
    }
}
```

It lowers to `signposter.measure("loadUsers") { try repo.all() }`. That call emits an `os_signpost` interval for Instruments, logs one timing entry through the signposter's logger, and records a span for the Diagnostics Hub when the signposter has a store (the one from `LogEnvironment.signposter` does).

I'll be honest: this macro saves less than `#log`. The direct call is just as short, and it also accepts a `tag:`, which the macro doesn't forward. I keep `#measure` because it reads consistently next to `#log` and the name must be a `StaticString` literal either way.

### `@AutoLog` — a helper, not magic

```swift
import SwiftMoLoggerSugar

@AutoLog
final class CheckoutService {
    let logger: MoLogger
    init(logger: MoLogger) { self.logger = logger }

    func purchase(_ id: String) throws {
        __autoLog()        // you add this line; the macro does not
        // …
    }
}
```

Here's exactly what it does. `@AutoLog` adds one member to the type, as long as the type has at least one method:

```swift
@inline(__always)
fileprivate func __autoLog(_ method: String = #function,
                           file: String = #fileID,
                           line: Int = #line) {
    logger.trace("→ \(method)", tag: .Development.debug, file: file, function: method, line: line)
}
```

Call `__autoLog()` as the first line of a method and you get a trace entry like `→ purchase(_:)`, with the right file and line. The helper logs through the type's own `logger` property, so the type must have a `logger: MoLogger`, under that exact name.

Here's what it does *not* do. It doesn't log every method automatically. It doesn't log exits or thrown errors, and it doesn't add signposts. The macro is also declared with a member-attribute role, but that role currently adds nothing to any member. A method without the `__autoLog()` line is silent.

That's deliberate. Rewriting function bodies with macros is still an unsettled corner of Swift, and code that rewrites every adopter's methods is code that breaks on some adopter's compiler. A helper is the stable middle ground: you opt in per method, with one short line you can grep for.

### The opt-in cost

Swift Macros need `swift-syntax` at build time. It's a large dependency and it noticeably lengthens clean builds. Forcing every adopter to pay that would be hostile.

So the macros live in their own library product, `SwiftMoLoggerSugar`, backed by a separate macro target. It re-exports `SwiftMoLogger`, so one import gives you both. Teams who want the macros add:

```swift
.product(name: "SwiftMoLoggerSugar", package: "SwiftMoLogger")
```

Teams who don't depend on `SwiftMoLogger` alone and never build `swift-syntax`. The supported range is `509.0.0..<605.0.0`, wide on purpose, so the macros don't force a `swift-syntax` version that clashes with other packages in your app. That covers Swift 5.9 through Swift 6.4. Both paths work; the choice is the team's, not the library's.

## What these two pieces share

They both target a category I call **dev-experience surface area**. They don't make your code run faster, they don't catch new bugs, they don't add a new sink. They make the moments around logging — typing the call, reading the output across devices — cheaper.

Dev experience is undervalued in iOS tooling. We accept slow compile cycles, hand-rolled URLSession capture, and ad-hoc breakpoints because that's how it's always been. SwiftMoLogger's bet is that an afternoon saved on device setup, and one fewer hand-typed source location, compound across a team into velocity you can't buy back any other way.

Previous: [Instruments in your app: building Diagnostics Hub](03-diagnostics-hub.md). Next: [05-production-playbook.md](05-production-playbook.md).

→ See [`Sources/SwiftMoLoggerDiagnostics/LiveSink.swift`](../Sources/SwiftMoLoggerDiagnostics/LiveSink.swift), [`Sources/SwiftMoLoggerInspector/Inspector.swift`](../Sources/SwiftMoLoggerInspector/Inspector.swift) and [`Sources/SwiftMoLoggerMacros/`](../Sources/SwiftMoLoggerMacros) for the implementation.
