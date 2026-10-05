# Instruments in your app: building Diagnostics Hub

> The bug only repros on TestFlight, on a colleague's iPad, with airplane mode toggled at the wrong moment. You can't attach Xcode. You can't run Instruments. You have a screenshot and a feeling.

This is the situation that motivated `DiagnosticsHubView`. The thesis: if every signal an iOS engineer cares about (logs, network requests, signpost spans, CPU/memory/FPS, breadcrumbs) is already a `Sendable` value in the app's memory, why does looking at them require a Mac?

```swift
import SwiftMoLogger
import SwiftMoLoggerUI

struct DebugTab: View {
    let logging: LogEnvironment   // injected from your App
    var body: some View { DiagnosticsHubView(environment: logging) }
}
```

That's it. The same kind of data Instruments shows you, in a SwiftUI view you can drop into any debug screen of any build.

## The architecture

The Hub has one rule: **never own the data**. In 4.0 there are no `.shared` stores. One `LogEnvironment`, created at your composition root, owns the registry, the logger and the four diagnostics stores. The Hub only reads them.

Think of a building's security system. The stores are cameras recording onto loop tapes. The Hub is the monitor room: it records nothing, it just plays the tapes.

The producers each receive the piece they record into:

```swift
import SwiftMoLogger
import SwiftMoLoggerNetwork
import SwiftMoLoggerDiagnostics

let logging = LogEnvironment()

// Network waterfall
let network = NetworkLogger(environment: logging)
let session = URLSession(configuration: .default, delegate: network, delegateQueue: nil)

// Flame graph
let signposter = logging.signposter
let users = try signposter.measure("loadUsers") { try userRepository.all() }

// Vitals charts (keep a strong reference, or sampling stops)
let vitals = AppVitalsMonitor(logger: logging.logger, history: logging.vitals)
vitals.start(interval: 1)

// Breadcrumbs
logging.breadcrumbs.record("tapped Checkout", category: .userAction)
```

The rule that matters with injection: **feed and read from the same environment**. A `NetworkLogger` built from another `LogEnvironment` writes to another store, and the waterfall stays empty.

### Loop tapes, not archives

Each store is a fixed-capacity ring buffer behind an `UnfairLock`. When full, the oldest item is overwritten, like a loop tape. Defaults: 500 network events, 500 spans, 600 vitals ticks, 100 breadcrumbs (pass your own `capacity:` stores to `LogEnvironment`). `record(_:)` is O(1), and `snapshot()` returns a value-typed `Array`. Nothing mutable escapes the lock.

### The view model

`HubViewModel` (`@MainActor`, `ObservableObject`) polls every 500 ms by default, snapshots every store and publishes the results. It polls only while the Hub is on screen (`start()` on appear, `stop()` on disappear). The tick is the throttle: a burst of logs never becomes a burst of SwiftUI updates.

The Logs tab is the exception to "never own the data". The view model registers its own `MemoryLogEngine` (2,000 entries by default) with `environment.registry`, and removes it in `deinit`. Older versions left it behind whenever a Hub closed, still receiving every line.

One consequence: the Logs tab only holds entries logged after the model was created. For history from launch, create a `HubViewModel(environment:)` early, keep it alive, and show it with `DiagnosticsHubView(model:)`.

## The unifying abstraction: `scrubbedTime`

Every sub-view filters its data through:

```swift
public func inWindow(_ timestamp: Date) -> Bool {
    timestamp >= windowStart && timestamp <= windowEnd
}
```

`windowEnd` is `scrubbedTime ?? Date()`, so `nil` means live tail, over a 60-second window by default. Drag the slider in `TimelineScrubberView` (it reaches back 10 minutes) and `scrubbedTime` becomes a fixed instant. Every sub-view now shows that moment: requests in flight, spans running, memory at the time. "Live" snaps back.

This is the **time-travel** part: rewinding every tape at once. It's one `Date` shared by five views, but "what was happening right before the crash?" becomes "drag the slider to the crash entry and look around."

## The five tabs

### Logs

A `LazyVStack` of `LogEntryRowView`s from the Hub's memory engine, filtered by `inWindow`. The scrubber draws a per-second density bar from the same entries. For just a console, use `LogConsoleView(stream: logging.stream)`.

### Network waterfall

Each `NetworkEvent` becomes a row, something like:

```
GET users         ████░░░░░░  142ms  [200]
POST checkout     ████████░░  423ms  [201]
GET products      ███████████ 891ms  [500]
```

Offset encodes start time within the window; width encodes duration. Colour follows status: green 2xx, yellow 3xx, orange 4xx, red for 5xx or a transport error. Tap a row for method, URL, status, sizes, duration, error and timestamps.

The data comes from `NetworkLogger`, which records each task when `urlSession(_:task:didFinishCollecting:)` fires. Use it on a session you own, or per request: `URLSession.shared.data(for: request, delegate: network)`. It only observes, and redacts URLs before they reach the store (see `NetworkLogger(environment:urlRedaction:)`).

### Signpost flame graph

Greedy lane assignment: walk spans by start time and put each in the lowest lane whose occupant has already ended. Concurrent spans stack; sequential spans share a lane.

```swift
private func laneAssignments(for events: [SignpostEvent]) -> [UUID: Int] {
    var laneEnds: [Date] = []
    var result: [UUID: Int] = [:]
    for event in events.sorted(by: { $0.startedAt < $1.startedAt }) {
        if let lane = laneEnds.firstIndex(where: { $0 <= event.startedAt }) {
            laneEnds[lane] = event.endedAt
            result[event.id] = lane
        } else {
            laneEnds.append(event.endedAt)
            result[event.id] = laneEnds.count - 1
        }
    }
    return result
}
```

Colour encodes duration: blue up to 50 ms, orange up to 250 ms, red above. The spans come from `environment.signposter`, a `Signposter` wired to the environment's logger and signpost store. One `measure` gives you an Instruments interval, a timing log entry and a flame-graph bar.

### Vitals charts

Memory, CPU and FPS line charts, rendered with Swift Charts:

```swift
Chart(ticks) { tick in
    LineMark(x: .value("t", tick.timestamp), y: .value("MB", tick.memoryMB))
}
```

Where Charts is unavailable, a summary card shows the latest values. The data is `environment.vitals.snapshot()`, fed by `AppVitalsMonitor(logger:history:)` once you call `start(interval:)`.

Two quiet monitor bugs are fixed in 4.0. Its `CADisplayLink` retained the monitor, keeping it alive until `stop()`; a proxy now holds it weakly. And on ProMotion it held the screen at 120 Hz just to count frames; the link is now capped at 60 Hz, so FPS is measured against 60.

### Breadcrumbs trail

A vertical timeline of `Breadcrumb`s, a coloured dot per category, synced to the same window. This is the "what was the user doing before this happened" view. `NetworkLogger` adds a crumb per request and response, so trail and waterfall line up.

The Hub also builds for tvOS and watchOS and degrades gracefully: tvOS has no `Slider`, so the scrubber uses step buttons, and FPS is only measured on iOS and tvOS.

## Why one view, not a separate Mac app

A desktop tool (Charles, Pulse, Bagel) is genuinely useful, but every QA engineer needs to install it, configure proxies, trust certificates and run a Mac. The on-device Hub skips all of that. Anybody who can install your TestFlight build can open the debug tab.

The `swiftmologger-inspector` CLI complements it, tailing logs from devices running a `LiveSink` over Bonjour. But it's not the *primary* surface. The Hub is.

## What I'd add next

- **Diff mode.** Two windows, side by side, with deltas highlighted. "What changed between this run and the last successful one?"
- **Export as `.trace`.** Hand off to real Instruments for deep dives.
- **Replay from a `FlightRecorder` file.** Crash recovered? Load the recorded session into the Hub and scrub through what happened.

The third is closer than it looks: since stores are injected, a recovered session could be poured into a fresh `LogEnvironment` and handed to the Hub. The Flight Recorder is covered in [the production playbook](05-production-playbook.md); next up is [Bonjour and Swift Macros](04-bonjour-and-macros.md).

→ See [`Sources/SwiftMoLoggerUI/Hub/`](../Sources/SwiftMoLoggerUI/Hub) for the implementation, the [README](../README.md) for setup, and [MIGRATION.md](../MIGRATION.md) if you're coming from 3.x.
