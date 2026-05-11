# Instruments in your app: building Diagnostics Hub

> The bug only repros on TestFlight, on a colleague's iPad, with airplane mode toggled at the wrong moment. You can't attach Xcode. You can't run Instruments. You have a screenshot and a feeling.

This is the situation that motivated `DiagnosticsHubView`. The thesis: if every signal an iOS engineer cares about — logs, network requests, signpost spans, CPU/memory/FPS, breadcrumbs — is already a `Sendable` value in the app's memory, why does looking at them require a Mac?

```swift
import SwiftMoLoggerUI

struct DebugTab: View {
    var body: some View { DiagnosticsHubView() }
}
```

That's it. The same data Instruments would show you, in a SwiftUI view you can drop into any debug screen of any build.

## The architecture

The Hub has one rule: **never own the data**. Each signal already has a shared `Store` in the core target:

```
NetworkEventStore.shared      ← NetworkLoggingProtocol records here
SignpostEventStore.shared     ← LogSignpost.measure records here
VitalsHistoryStore.shared     ← AppVitalsMonitor records here
BreadcrumbStore.shared        ← SwiftMoLogger.breadcrumb records here
MemoryLogEngine               ← engineCount controlled by HubViewModel
```

Each store is a fixed-capacity ring buffer guarded by `os_unfair_lock`. `record(_:)` is O(1). `snapshot()` returns a value-typed `Array`. No retain cycles, no shared mutable state escapes the lock.

The `HubViewModel` (`@MainActor ObservableObject`) polls every 500 ms, pulls a snapshot from each store, and publishes them as `@Published` properties. SwiftUI rebuilds the affected sub-views and that's it. The 500 ms tick is the throttle that keeps the UI thread untouched even when 10 000 log entries land per second.

## The unifying abstraction: `scrubbedTime`

Every sub-view filters its data through:

```swift
public func inWindow(_ timestamp: Date) -> Bool {
    timestamp >= windowStart && timestamp <= windowEnd
}
```

`windowEnd` defaults to `Date()` (live tail). When the user drags the slider in `TimelineScrubberView`, `model.scrubbedTime` becomes a fixed instant and every sub-view shows you that moment's reality — the network requests that were in flight, the signpost spans that were open, the memory level at the time.

This is the **time-travel** part. It's not a complicated abstraction — it's a `Date` shared by five views — but the effect on debugging is dramatic. "What was happening right before the crash?" becomes "drag the slider until the crash entry, look around."

## The five tabs

### Logs

A `LazyVStack` of `LogEntryRowView`s filtered by `inWindow`. The view is intentionally simple — the heavy lifting (filtering by level, search, pause) lives on the existing `LogConsoleViewModel` that the Hub composes.

### Network waterfall

Each `NetworkEvent` becomes a row:

```
GET /v1/users         ████░░░░░░  142ms  [200]
POST /v1/checkout     ████████░░  423ms  [201]
GET /v1/products      ███████████ 891ms  [500]
```

The bar's `x` position encodes start time relative to the window; the bar's width encodes duration. Status family drives colour (`200..<300` green, `400..<500` orange, `500..<600` red). Tap a row → sheet with the full request/response/error detail.

The data comes from `NetworkEventStore.shared`, which the `NetworkLoggingProtocol` records into on every request completion. So you opt into the waterfall by installing the protocol — nothing else.

### Signpost flame graph

Spans laid out via greedy lane assignment: walk events sorted by start time; place each in the lowest lane whose current occupant has already ended. Concurrent spans stack vertically; sequential spans share a lane.

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

Span colour encodes duration tier: blue (< 50 ms), orange (< 250 ms), red (≥ 250 ms). The signposts come from `LogSignpost.measure` — same call you'd use for Instruments integration — so wiring an existing app costs nothing.

### Vitals charts

Three line charts: memory_MB, cpu_pct, fps. On iOS 16+ they render via Swift Charts:

```swift
Chart(ticks) { tick in
    LineMark(x: .value("t", tick.timestamp),
             y: .value("MB", tick.memoryMB))
}
```

On iOS 15 there's a summary card fallback. Either way, the data is `VitalsHistoryStore.shared.snapshot()` — a value-typed array of `VitalsTick`. The store is fed by `AppVitalsMonitor.shared.start(interval:)`.

### Breadcrumbs trail

A vertical timeline of `Breadcrumb`s, with a coloured dot per category and a connecting line between them. Synced to the same window as everything else. This is the "what was the user doing before this happened" view.

## Why one view, not a separate Xcode app

A separate desktop tool (Charles / Pulse / Bagel) is genuinely useful, but it has a cost: every QA engineer needs to install it, configure proxies, accept root certificates, and run a Mac. The on-device Hub bypasses all of that. Anybody who can install your TestFlight build can open the debug tab and see what happened.

The Mac CLI in `SwiftMoLoggerInspector` complements the Hub — it's there for the times when you do want a multi-device dashboard on a real screen. But it's not the *primary* surface. The Hub is.

## What I'd add next

- **Diff mode.** Two windows, side by side, with deltas highlighted. "What changed between this run and the last successful one?"
- **Export as `.trace`.** Hand off to real Instruments for deep dives.
- **Replay from a `FlightRecorder` file.** Crash recovered? Load the recorded session into the Hub and scrub through what happened.

The third one is closer than it looks — it's the next article's topic.

→ See [`Sources/SwiftMoLoggerUI/Hub/`](../Sources/SwiftMoLoggerUI/Hub) for the implementation.
