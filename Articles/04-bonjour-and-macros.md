# Zero-config debugging with Bonjour and Swift Macros

> Half of what a senior iOS engineer spends their day on is *not* writing iOS code. It's reading logs, ten devices at a time, on a flaky office Wi-Fi, while someone keeps unplugging the cable.

This article is about the two parts of v3 that exist to make that day shorter: a Bonjour-advertised live tail, and a small set of Swift Macros that make the call sites painless.

## Bonjour: the cable nobody plugs in

The standard iOS debugging loop is *plug in the device → trust the certificate → reload Xcode → open Console → filter by subsystem*. Each step has failure modes. Each step gets tedious when you have to do it three times a day across a fleet of QA devices.

The version of the loop I wanted is: *open Terminal, run one command, see every device's logs immediately*.

### The iOS side

On the device, `LiveSink` is a `LogEngine` that opens an `NWListener` and advertises itself via Bonjour:

```swift
public final class LiveSink: LogEngine {
    public static let serviceType = "_swiftmologger._tcp"

    public func start() throws {
        let listener = try NWListener(using: .tcp, on: port)
        listener.service = NWListener.Service(name: serviceName, type: LiveSink.serviceType)
        listener.newConnectionHandler = { [weak self] in self?.accept($0) }
        listener.start(queue: queue)
    }

    public func log(_ entry: LogEntry) {
        guard let data = try? encoder.encode(entry) else { return }
        var line = data; line.append(0x0A)
        for client in connectedClients {
            client.send(content: line, completion: .contentProcessed { _ in })
        }
    }
}
```

JSON-Lines over TCP. No framing protocol, no handshake beyond Bonjour discovery. The on-device cost is negligible — `NWListener` is part of Apple's `Network.framework`, the JSON encoder is already in your binary, and we send to whoever is connected.

### The Mac side

`swiftmologger-inspector` is an executable target. It uses `NWBrowser` to discover every device advertising `_swiftmologger._tcp` and opens an `NWConnection` to each:

```swift
let browser = NWBrowser(for: .bonjour(type: "_swiftmologger._tcp", domain: nil), using: parameters)
browser.browseResultsChangedHandler = { results, _ in
    for case .service(let name, _, _, _) in results.map(\.endpoint) {
        connect(to: result.endpoint, name: name)
    }
}
```

Each incoming line is decoded and rendered with ANSI colour by level and by device name. The terminal output looks like:

```
SwiftMoLogger Inspector — discovering _swiftmologger._tcp on local network…
◉ discovered MyApp-iPhone-15
◉ discovered MyApp-iPad-Pro
● connected MyApp-iPhone-15
● connected MyApp-iPad-Pro

14:22:01.124 INFO  MyApp-iPhone-15 [API]     HTTP response status=200 duration_ms=132
14:22:01.221 WARN  MyApp-iPad-Pro  [Layout]  Auto-layout broke 3 constraints
14:22:01.337 ERROR MyApp-iPhone-15 [DB]      Migration v4 → v5 timed out
```

No certificates, no cables, no Xcode. Run `swift run swiftmologger-inspector` and start watching. The implementation is ~150 lines of `Network.framework` because Apple's APIs are good when you let them be.

A practical safety note: **only enable `LiveSink` in DEBUG builds**. It opens a local network port and emits log lines in the clear. The `LiveSink.swift` doc comment is explicit about this and the README repeats it.

## Swift Macros: the call site you don't have to think about

The other half of the daily loop is *typing log statements*. With v3, the bare API is already good:

```swift
SwiftMoLogger.info("user signed in", tag: .api,
                   metadata: ["user_id": .string(user.id)])
```

But that's a lot of structure for a `print("user signed in")` replacement. Swift Macros let us reduce it without losing what makes the structured call valuable.

### `#log` — captures source location at the call site

```swift
import SwiftMoLoggerSugar

#log("user signed in", level: .info, tag: .api)
```

The macro expansion is exactly what you'd write by hand, with `#fileID` / `#function` / `#line` captured at the call site rather than in the library:

```swift
SwiftMoLogger.log(.info, "user signed in", tag: .api,
                  file: #fileID, function: #function, line: #line)
```

Why does that matter when you could already write it? Because the macro lets you build code-mod tools that grep for `#log` invocations without parsing argument lists, and the IDE shows you the expansion in-place. It's also easier to teach a new contributor to write `#log("x")` than to remember the whole structured shape.

### `#measure` — never typo a signpost name again

```swift
let users = #measure("loadUsers") {
    try repo.all()
}
```

Lowers to `LogSignpost.measure("loadUsers") { … }`. Same call, but the macro means the signpost name is in the IR before the optimiser ever sees the closure — making it stable and grep-able.

### `@AutoLog` — class-wide entry/exit logging

```swift
@AutoLog
final class CheckoutService {
    func purchase(_ id: String) throws { … }
}
```

The macro is a `MemberMacro` that synthesises a `fileprivate __autoLog(method:)` helper inside the type, which methods can call at their entry. Macro-driven body rewriting is still an unstable Swift surface — touching it would make the library brittle across compiler versions — so I deliberately stopped at the helper. The convention is `__autoLog()` as the first line of a traced method; it's three keystrokes and you can grep for it.

### The opt-in cost

Swift Macros require `swift-syntax` as a build-time dependency. `swift-syntax` is large (~100 MB compiled) and meaningfully extends clean-build times. Forcing every adopter of `SwiftMoLogger` to pay that cost would be hostile.

The macros live in a separate library product, `SwiftMoLoggerSugar`, with its own target that depends on the macro plugin. Adopters who want them write:

```swift
.product(name: "SwiftMoLoggerSugar", package: "SwiftMoLogger")
```

Adopters who don't write `SwiftMoLogger` and never see `swift-syntax`. Both paths work; the choice is the team's, not the library's.

## What these two pieces share

They both target a category I call **dev-experience surface area**. They don't make your code run faster, they don't catch new bugs, they don't add a new sink. They make the moments around logging — typing the call, reading the output across devices — cheaper.

Dev experience is undervalued in iOS tooling. We accept five-minute compile cycles, hand-rolled URLSession capture, and ad-hoc breakpoints because that's how it's always been. SwiftMoLogger's bet is that a single afternoon saved on Bonjour discovery and a single fewer typo on a signpost name compounds, across a team, into the kind of velocity you can't buy back any other way.

→ See [`Sources/SwiftMoLoggerInspector/Inspector.swift`](../Sources/SwiftMoLoggerInspector/Inspector.swift) and [`Sources/SwiftMoLoggerMacros/`](../Sources/SwiftMoLoggerMacros) for the implementation.
