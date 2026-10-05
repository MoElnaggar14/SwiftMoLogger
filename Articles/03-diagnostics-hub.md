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

I think of it like a building's security system. The stores are cameras recording onto loop tapes. The producers are whatever walks past the cameras. The Hub is the monitor room: it doesn't record anything, it just shows you the tapes.

```
environment.networkEvents  ← NetworkLogger (a URLSessionTaskDelegate you inject)
environment.signposts      ← environment.signposter.measure / measureAsync / makeInterval
environment.vitals         ← AppVitalsMonitor(logger:history:)
environment.breadcrumbs    ← breadcrumbs.record(…), plus NetworkLogger
MemoryLogEngine            ← registered by HubViewModel for the Logs tab
```

Here is the whole wiring:

```swift
import SwiftMoLogger
import SwiftMoLoggerNetwork
import SwiftMoLoggerDiagnostics

let logging = LogEnvironment()

// Network waterfall: hand the logger to the sessions you create.
let network = NetworkLogger(environment: logging)
let session = URLSession(configuration: .default, delegate: network, delegateQueue: nil)

// Flame graph: every measured span lands in logging.signposts.
let signposter = logging.signposter
let users = try signposter.measure("loadUsers") { try userRepository.all() }

// Vitals charts: keep a strong reference, or sampling stops.
let vitals = AppVitalsMonitor(logger: logging.logger, history: logging.vitals)
vitals.start(interval: 1)

// Breadcrumbs trail.
logging.breadcrumbs.record("tapped Checkout", category: .userAction)
```

The one rule that matters with injection: **feed and read from the same environment**. A `NetworkLogger` built from a different `LogEnvironment` writes to a different store, and the waterfall stays empty.

### Loop tapes, not archives

Each store is a fixed-capacity ring buffer behind a heap-allocated `UnfairLock`. When it's full, the oldest item is overwritten, just like a loop tape. The defaults are 500 network events, 500 signpost spans, 600 vitals ticks and 100 breadcrumbs, and each store takes `capacity:` if you want more. `record(_:)` is O(1), and `snapshot()` returns a plain value-typed `Array`. Nothing mutable escapes the lock.

### The view model

`HubViewModel` (`@MainActor`, `ObservableObject`) polls every 500 ms by default. Each tick it takes a snapshot of every store and publishes them. It only polls while the Hub is on screen: the view calls `start()` on appear and `stop()` on disappear. The tick is the throttle. A burst of logs never turns into a burst of SwiftUI updates.

The Logs tab is the exception to "never own the data". The view model registers its own `MemoryLogEngine` (2,000 entries by default) with `environment.registry` when it's created, and removes it again in `deinit`. In 3.x, every Hub you opened and closed left its engine behind, still receiving every log line. Now each Hub cleans up after itself.

One consequence: the Logs tab starts empty when the model is created. If you want history from app launch, own the model yourself and keep it alive:

```swift
@main
struct ShopApp: App {
    private let logging: LogEnvironment
    @StateObject private var hub: HubViewModel

    init() {
        let logging = LogEnvironment()
        self.logging = logging
        _hub = StateObject(wrappedValue: HubViewModel(environment: logging))
    }

    var body: some Scene {
        WindowGroup { DiagnosticsHubView(model: hub) }
    }
}
```

## The unifying abstraction: `scrubbedTime`

Every sub-view filters its data through:

```swift
public func inWindow(_ timestamp: Date) -> Bool {
    timestamp >= windowStart && timestamp <= windowEnd
}
```

`windowEnd` is `scrubbedTime ?? Date()`, so `nil` means live tail. The window is 60 seconds wide by default. When you drag the slider in `TimelineScrubberView` (it reaches back 10 minutes), `scrubbedTime` becomes a fixed instant. Every sub-view then shows you that moment: the requests in flight, the spans that were running, the memory level at the time. A "Live" button snaps back.

This is the **time-travel** part, or in the analogy, rewinding every tape at once. It's not a complicated abstraction. It's one `Date` shared by five views. But "what was happening right before the crash?" becomes "drag the slider to the crash entry and look around."

## The five tabs

### Logs

A `LazyVStack` of `LogEntryRowView`s from the Hub's memory engine, filtered by `inWindow`. The scrubber above it draws a density bar from the same entries, one column per second. If you only want a plain console, `LogConsoleView(stream: logging.stream)` is the lighter option.

### Network waterfall

Each `NetworkEvent` becomes a row, something like:

```
GET users         ████░░░░░░  142ms  [200]
POST checkout     ████████░░  423ms  [201]
GET products      ███████████ 891ms  [500]
```

The bar's offset encodes start time inside the window, and its width encodes duration. Colour follows the status family: green for 2xx, yellow for 3xx, orange for 4xx, red for 5xx or any transport error. Tap a row for a sheet with method, URL, status, request and response sizes, duration, error and timestamps.

The data comes from `NetworkLogger`. It reports each task's outcome from `urlSession(_:task:didFinishCollecting:)`, which also fires for tasks made with the async and completion-handler APIs. So it works on a session you own, or per request on any session: `URLSession.shared.data(for: request, delegate: network)`. It only observes. URLs are redacted before they reach the store (`NetworkLogger(environment:urlRedaction:)` lets you pick `.withoutQuery` or `.full`).

### Signpost flame graph

Spans are laid out by greedy lane assignment. Walk the spans sorted by start time, and put each one in the lowest lane whose current occupant has already ended. Concurrent spans stack vertically, and sequential spans share a lane.

```swift
private func laneAssignments(for events: [SignpostEvent]) -> [UUID: Int] {
    var laneEnds: [Date] = []
    var result: [UUID: Int] = [:]
    let sorted = events.sorted { $0.startedAt < $1.startedAt }
    for event in sorted {
        var assignedLane: Int?
        for (index, end) in laneEnds.enumerated() where end <= event.startedAt {
            assignedLane = index
            break
        }
        if let lane = assignedLane {
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

Colour encodes duration: blue up to 50 ms, orange up to 250 ms, red above that. The spans come from `Signposter`, the same call that emits `os_signpost` intervals for Instruments. `environment.signposter` is built with the environment's logger and signpost store, so one `measure` gives you an Instruments interval, a timing log entry and a flame-graph bar.

### Vitals charts

Memory, CPU and FPS line charts, rendered with Swift Charts:

```swift
Chart(ticks) { tick in
    LineMark(x: .value("t", tick.timestamp), y: .value("MB", tick.memoryMB))
}
```

Where Charts isn't available, a summary card shows the latest memory, CPU, FPS, thermal state and battery. Either way, the data is `environment.vitals.snapshot()`, an array of `VitalsTick`, fed by `AppVitalsMonitor(logger:history:)` and `start(interval:)`.

The monitor had two quiet bugs in earlier versions, both fixed in 4.0. Its `CADisplayLink` retained the monitor, so it lived until you called `stop()`. Now a small proxy holds it weakly. And on ProMotion screens it kept the display at 120 Hz just to count frames. The link is now capped at 60 Hz, so FPS is measured against 60. It also restores the app's battery-monitoring setting after each read.

### Breadcrumbs trail

A vertical timeline of `Breadcrumb`s, with a coloured dot per category and a line between them. It's synced to the same window as everything else. This is the "what was the user doing before this happened" view. `NetworkLogger` adds a breadcrumb per request and response, so the trail and the waterfall line up.

### Beyond iOS

The Hub and the vitals monitor build for tvOS and watchOS too, and degrade where a control or measurement doesn't exist. On tvOS, which has no `Slider`, the scrubber becomes step buttons. FPS is only measured on iOS and tvOS, and battery only on iOS.

## Why one view, not a separate Mac app

A separate desktop tool (Charles, Pulse, Bagel) is genuinely useful, but it has a cost. Every QA engineer needs to install it, configure proxies, trust certificates and run a Mac. The on-device Hub skips all of that. Anybody who can install your TestFlight build can open the debug tab and see what happened.

The `swiftmologger-inspector` CLI complements the Hub. It discovers devices running a `LiveSink` over Bonjour and tails their logs on your Mac, which is great when you do have a real screen nearby. But it's not the *primary* surface. The Hub is.

## What I'd add next

- **Diff mode.** Two windows, side by side, with deltas highlighted. "What changed between this run and the last successful one?"
- **Export as `.trace`.** Hand off to real Instruments for deep dives.
- **Replay from a `FlightRecorder` file.** Crash recovered? Load the recorded session into the Hub and scrub through what happened.

The third one is closer than it looks. Because the stores are injected, a recovered session could be poured into a fresh `LogEnvironment` and handed to the Hub. The Flight Recorder itself is covered in [the production playbook](05-production-playbook.md); next up is [zero-config debugging with Bonjour and Swift Macros](04-bonjour-and-macros.md).

→ See [`Sources/SwiftMoLoggerUI/Hub/`](../Sources/SwiftMoLoggerUI/Hub) for the implementation, the [README](../README.md) for setup, and [MIGRATION.md](../MIGRATION.md) if you're coming from 3.x.
