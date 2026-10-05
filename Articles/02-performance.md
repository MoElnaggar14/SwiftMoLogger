# Sub-µs logging: the performance design

> "Logging is fine, it doesn't show up in profiles." — every team, ten seconds before logging shows up in profiles.

The first version of SwiftMoLogger v2 used a concurrent `DispatchQueue` with barrier writes to protect its engine list. The second version inlined a copy of the engine array into every log call. Both worked. Neither was fast enough to log in a tight Metal render loop without showing up on a trace.

[PERFORMANCE.md](../PERFORMANCE.md) puts a log call with no engines attached at ~140 ns. This is the article on how it got there, and on what changed in 4.0, where the static facade is gone and every call goes through a `MoLogger` you inject from a `LogEnvironment`.

## What "fast" means for a logger

The hot path of a log call is the sequence of instructions that run *every time* you call `logger.info("…")`, whether the entry is kept, dropped, or fanned out. There are four budgets I care about:

1. **CPU time.** How many nanoseconds.
2. **Allocations.** How many heap objects materialise.
3. **Lock contention.** What blocks other threads.
4. **Argument evaluation.** Whether `"\(complexExpression())"` runs even when filtered.

A "fast" logger is one where dropping a call below the minimum level costs a level comparison and very little else: no string interpolation, no `Date()`, no `LogEntry`.

## The lock that isn't a queue

v2 used:

```swift
let queue = DispatchQueue(label: "registry", qos: .utility, attributes: .concurrent)

func allEngines() -> [LogEngine] {
    queue.sync { Array(engines) }
}
```

That `sync` hop is far heavier than an uncontended lock, and `Array(engines)` allocates. **Every log call paid that.**

From v3 on, the registry uses `os_unfair_lock`. This is `EngineRegistry.dispatch(_:)` in 4.0:

```swift
public func dispatch(_ entry: LogEntry) {
    lock.lock()
    let level = globalMinimumLevel
    guard entry.level >= level else {
        lock.unlock()
        return
    }
    let snapshot = engines      // ContiguousArray<any LogEngine>
    lock.unlock()

    let ambient = LogContext.current
    let merged: LogEntry
    if ambient.isEmpty {
        merged = entry
    } else {
        merged = LogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level,
            message: entry.message,
            tag: entry.tag,
            metadata: ambient.merging(entry.metadata),
            source: entry.source,
            threadName: entry.threadName
        )
    }

    for engine in snapshot where merged.level >= engine.minimumLevel {
        engine.log(merged)
    }
}
```

The critical section is one comparison and one array copy. Copying a `ContiguousArray` doesn't copy its elements: it retains the shared buffer, and copy-on-write means a later `addEngine` builds a new buffer instead of touching the one we're iterating. So the snapshot is a photograph of the guest list, not the list itself. The bouncer checks your name at the door and goes back to his post; he doesn't walk you to the bar. Fan-out happens **outside** the lock, so a slow engine can't stall the next caller, and the task-local `LogContext` merge happens outside it too.

The registry's own notes credit this change with ~3× lower per-call cost than the old barrier queue.

### The 3.1 fix: a lock needs an address

v3 shipped this as `private var lock = os_unfair_lock_s()` and called `os_unfair_lock_lock(&lock)`. That looks right and is undefined behaviour. `&` on a stored Swift property doesn't promise a stable address; the compiler may pass a pointer to a temporary copy. Two threads can then each lock their own copy, and the lock silently does nothing. It's like agreeing to meet "at the whiteboard" when everyone has been handed their own photocopy of it.

Thirteen types had this pattern. 3.1 replaced all of them with a small heap-allocated wrapper (`Sources/SwiftMoLogger/Core/UnfairLock.swift`, abridged):

```swift
package final class UnfairLock: @unchecked Sendable {
    private let pointer: os_unfair_lock_t

    package init() {
        pointer = .allocate(capacity: 1)
        pointer.initialize(to: os_unfair_lock())
    }

    package func lock() { os_unfair_lock_lock(pointer) }
    package func unlock() { os_unfair_lock_unlock(pointer) }
}
```

The lock is allocated once, when the registry is created, and never moves. The hot path pays nothing extra for that: no allocation, just a call through a pointer it already holds.

## Filtering before allocation

In 3.0 the level helpers looked like this:

```swift
public static func info(_ message: @autoclosure () -> String, …) {
    log(.info, message(), …)   // evaluates message() here
}
```

The `@autoclosure` was decorative: `info` called `message()` to hand a `String` to `log()`. If your call was `info("user \(expensiveDescribe(user))")`, the expensive work ran whether or not the entry was kept.

In 4.0 every level helper still forwards `message()`, but it forwards it into another `@autoclosure` parameter, so nothing runs yet. The first real work happens in `MoLogger.log`:

```swift
public func log(
    _ level: LogLevel,
    _ message: @autoclosure () -> String,
    tag: LogTag? = nil,
    metadata: LogMetadata = [:],
    …
) {
    guard level >= registry.minimumLevel else { return }
    registry.dispatch(LogEntry(
        level: level,
        message: message(),
        tag: tag ?? self.tag,
        metadata: self.metadata.isEmpty ? metadata : self.metadata.merging(metadata),
        source: SourceLocation(file: file, function: function, line: line, column: column)
    ))
}
```

The level check comes first. The message closure, `UUID()`, `Date()`, the thread name and the `LogEntry` itself are only built once the entry survives the registry's minimum level. Reading `registry.minimumLevel` takes the same unfair lock, so a filtered call costs one short lock round trip, and a kept call takes the lock twice (once here, once in `dispatch`).

Two honest caveats:

- **`metadata` is not lazy.** It's a plain parameter, so `metadata: ["user": .string(expensiveDescribe(user))]` is evaluated at the call site *before* the level check. The same goes for the `error(_ error: any Error)` overload, which builds its `error_type` / `error` metadata before calling `log`. If a metadata value is expensive, check the level yourself or move it into the message.
- **`debug` is compiled out of release builds.** Its body is wrapped in `#if DEBUG`, so the message is never evaluated there. The call and its arguments (including metadata) are still there, though.

In production, set the level once at the composition root:

```swift
let logging = LogEnvironment()
logging.registry.minimumLevel = .info
logging.registry.addEngine(MemoryLogEngine(capacity: 500))

let log = logging.logger.with(tag: .api)

func didReceive(_ response: HTTPURLResponse) {
    log.trace("response \(response)")   // dropped before the string is built
}
```

## The shape of `LogEntry`

Several `LogEntry` choices have direct perf impact:

- `Sendable, Hashable, Codable, Identifiable` are conformances, not a class hierarchy. `LogEntry` is a struct: no reference counting of the entry itself.
- All fields are `let`. `LogMetadata` wraps a `Dictionary`, and empty dictionaries share one storage.
- `SourceLocation` comes from compile-time literals (`#fileID`, `#function`, `#line`, `#column`). No backtrace walk, no symbolication.
- The thread name checks `Thread.isMainThread` first and falls back to `Thread.current.name`. I deliberately avoided `Thread.current.description`, which allocates.

PERFORMANCE.md lists `LogEntry` at 200 B on the stack, with no heap traffic unless `metadata` is non-empty (the message string is its own matter: long interpolated strings allocate). Two things to know in 4.0: a child logger made with `with(metadata:)` merges its bound metadata into every entry, and an ambient `LogContext` is merged at dispatch. Both allocate a new dictionary per kept call. That's usually fine; it's not free.

## What the numbers look like

From [PERFORMANCE.md](../PERFORMANCE.md): release build, M1 MacBook Pro, iOS 17 simulator, measured by the benchmark tests in `Tests/SwiftMoLoggerTests/PerformanceBenchmarks.swift`:

| Scenario | per-call median | per-call p99 |
|---|---|---|
| `info("…")` — no engines | **~140 ns** | ~220 ns |
| `info("…")` — `MemoryLogEngine` only | **~310 ns** | ~460 ns |
| `info("…")` filtered by `minimumLevel = .error` | **~35 ns** | ~60 ns |
| `info("…")` — `SystemLogger` (os.log) only | **~820 ns** | ~1.3 µs |
| `info("…")` — 4 engines (System+Memory+File+Stream) | **~3.1 µs** | ~5.0 µs |
| Concurrent 8 threads × 2 000 calls | **~22 ms total** | linear scaling |

The filtered case is the most important one. Most production apps keep the level at `.info` and have hundreds of `trace` call sites peppered through the codebase. Those calls cost a level check and a return. You can leave them in.

`FileLogEngine` stays off this table for a reason: its `log(_:)` only enqueues the entry on a private serial queue (PERFORMANCE.md: ~80 ns), and encoding and disk writes happen off your thread.

## The Flight Recorder's bill

The Flight Recorder is a good test of the budget, because it's on in production. On the hot path it's just a `MemoryLogEngine` (default capacity 1,000): one append under its lock. The disk work runs on a timer, on a background queue.

In 3.0 that timer rewrote the whole file every 2 seconds, even when the app was idle, which was enough to trigger iOS disk-write warnings. Since 3.1 it fingerprints the newest item in each source and skips the encode and the write when nothing changed. The default interval is now 5 seconds, and it also flushes when the app goes to the background:

```swift
let recorder = FlightRecorder(environment: logging)   // flushInterval: 5 by default
recorder.start()
```

An idle app now costs a few array snapshots every 5 seconds and no disk I/O.

## Swift 6, and what I'd still like to improve

In 4.0 the library targets compile in the Swift 6 language mode with full data-race checking. `MoLogger` and `LogEnvironment` are `Sendable` structs, so passing a logger into a task or an actor is cheap and compiler-checked. The built-in engines are `@unchecked Sendable` classes; whatever mutable state they have sits behind an `UnfairLock` or a serial queue. That's where the compiler takes my word for it, which is exactly why the 3.1 lock fix mattered.

Two known overhangs:

1. **`os.log` is the floor for the system engine.** ~820 ns isn't us; it's `os_log` doing the formatting and routing through `logd`. Beating it means skipping `os_log` and losing `Console.app`. The tradeoff is right as it stands.

2. **Engines are still classes.** `LogEngine` requires `AnyObject` because some engines (`FileLogEngine`, `LiveSink`) need a long-lived identity for their worker queue, and the registry protects its default `SystemLogger` by identity (`===`). That costs one pointer load per engine in the fan-out loop. 4.0 kept it; a struct-based protocol would save the load but lose those engines.

The lesson is the one the JVM community learned about logging twenty years ago: **the cheapest call is the one that doesn't run**, and the way you get there is by making the filter the very first thing your call does. Everything else is plumbing.

→ See [`PERFORMANCE.md`](../PERFORMANCE.md) for the full benchmark table, and [`01-why-rewrite.md`](01-why-rewrite.md) for why the rewrite happened at all.
