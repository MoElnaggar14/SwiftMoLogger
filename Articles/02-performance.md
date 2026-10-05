# Sub-µs logging: the performance design

> "Logging is fine, it doesn't show up in profiles." — every team, ten seconds before logging shows up in profiles.

SwiftMoLogger v2 first protected its engine list with a concurrent `DispatchQueue` and barrier writes, then inlined a copy of the engine array into every call. Both worked. Neither was fast enough to log in a tight Metal render loop without showing up on a trace.

[PERFORMANCE.md](../PERFORMANCE.md) puts a log call with no engines attached at ~140 ns. This is how it got there, updated for 4.0, where every call goes through a `MoLogger` you inject from a `LogEnvironment`.

## What "fast" means for a logger

The hot path is what runs *every time* you call `logger.info("…")`. I care about four budgets:

1. **CPU time.** How many nanoseconds.
2. **Allocations.** How many heap objects materialise.
3. **Lock contention.** What blocks other threads.
4. **Argument evaluation.** Whether `"\(complexExpression())"` runs even when filtered.

A fast logger drops a filtered call for a level check and little else.

## The lock that isn't a queue

v2 used:

```swift
let queue = DispatchQueue(label: "registry", qos: .utility, attributes: .concurrent)

func allEngines() -> [LogEngine] {
    queue.sync { Array(engines) }
}
```

A `sync` hop is far heavier than an uncontended lock, and `Array(engines)` allocates. **Every log call paid that.**

Since v3 the registry uses `os_unfair_lock`. Here is `EngineRegistry.dispatch(_:)` in 4.0, abridged:

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

    // … merge the task-local LogContext into `merged` (skipped when it's empty) …

    for engine in snapshot where merged.level >= engine.minimumLevel {
        engine.log(merged)
    }
}
```

The critical section is one comparison and one array copy, which only retains the `ContiguousArray`'s buffer. Like a bouncer, the lock checks your name and returns to the door; it doesn't walk you to the bar. Fan-out happens **outside** the lock, so a slow engine can't stall the next caller.

The registry's notes credit this with ~3× lower per-call cost than the barrier queue.

### The 3.1 fix: a lock needs an address

v3 called `os_unfair_lock_lock(&lock)` on a stored `os_unfair_lock_s`. That looks right, and it's undefined behaviour. `&` on a stored Swift property doesn't promise a stable address; the compiler may pass a pointer to a temporary copy, and the lock silently does nothing. It's like agreeing to meet "at the whiteboard" when everyone got their own photocopy of it.

Thirteen types did this. 3.1 moved them all to a heap-allocated wrapper (`Core/UnfairLock.swift`, abridged):

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

The lock is allocated once, with its owner, and never moves.

## Filtering before allocation

In 3.0 the level helpers looked like this:

```swift
public static func info(_ message: @autoclosure () -> String, …) {
    log(.info, message(), …)   // evaluates message() here
}
```

The `@autoclosure` was decorative: calling `message()` there did the interpolation even when the entry was dropped.

In 4.0, `MoLogger.info` forwards into `log`'s own `@autoclosure`, so nothing runs yet, and `log` checks the level first (abridged):

```swift
guard level >= registry.minimumLevel else { return }
registry.dispatch(LogEntry(
    level: level,
    message: message(),
    tag: tag ?? self.tag,
    metadata: self.metadata.isEmpty ? metadata : self.metadata.merging(metadata),
    source: SourceLocation(file: file, function: function, line: line, column: column)
))
```

The message and the `LogEntry` are only built once the entry passes. Reading `minimumLevel` takes the registry's lock, so a filtered call is one short lock round trip; a kept call takes it twice.

Two honest caveats:

- **`metadata` is not lazy.** It's a plain parameter, evaluated at the call site *before* the level check (so is what `error(_ error: any Error)` builds). Keep expensive values in the message.
- **`debug` is compiled out of release builds**, so its message never runs there. Its metadata argument still does.

In production, set the level once at the composition root:

```swift
let logging = LogEnvironment()
logging.registry.minimumLevel = .info

let log = logging.logger.with(tag: .api)
log.trace("engines: \(logging.registry.allEngines())")   // never interpolated at .info
```

## The shape of `LogEntry`

- It's a struct with `let` fields: no reference counting of the entry itself.
- `SourceLocation` comes from compile-time literals (`#fileID`, `#function`, `#line`, `#column`), not a backtrace.
- The thread name checks `Thread.isMainThread` first, then `Thread.current.name`, avoiding the allocating `Thread.current.description`.

PERFORMANCE.md lists `LogEntry` at 200 B on the stack, with no heap traffic unless `metadata` is non-empty (a long message string allocates on its own). In 4.0, a child logger's `with(metadata:)` and an ambient `LogContext` each add a dictionary merge per kept call. Usually fine; not free.

## What the numbers look like

From [PERFORMANCE.md](../PERFORMANCE.md): release build, M1 MacBook Pro, iOS 17 simulator, measured by `Tests/SwiftMoLoggerTests/PerformanceBenchmarks.swift`:

| Scenario | per-call median | per-call p99 |
|---|---|---|
| `info("…")` — no engines | **~140 ns** | ~220 ns |
| `info("…")` — `MemoryLogEngine` only | **~310 ns** | ~460 ns |
| `info("…")` filtered by `minimumLevel = .error` | **~35 ns** | ~60 ns |
| `info("…")` — `SystemLogger` (os.log) only | **~820 ns** | ~1.3 µs |
| Concurrent 8 threads × 2 000 calls | **~22 ms total** | linear scaling |

The filtered case matters most: hundreds of `trace` call sites in an app running at `.info` cost a level check each. You can leave them in.

`FileLogEngine.log(_:)` only enqueues onto a serial queue (~80 ns per PERFORMANCE.md); disk work happens off your thread.

## The Flight Recorder's bill

On the hot path the Flight Recorder is a `MemoryLogEngine` (capacity 1,000 by default): one append under a lock. Disk work runs on a background timer.

In 3.0 that timer rewrote the file every 2 seconds, even when idle, enough for iOS disk-write warnings. Since 3.1 it skips the encode and the write when nothing changed, ticks every 5 seconds by default, and flushes when the app is backgrounded:

```swift
let recorder = FlightRecorder(environment: logging)   // flushInterval defaults to 5
recorder.start()
```

## Swift 6, and what I'd still like to improve

4.0's library targets compile in Swift 6 mode with full data-race checking. `MoLogger` and `LogEnvironment` are `Sendable` structs. Engines are `@unchecked Sendable` classes guarding state with an `UnfairLock` or a serial queue: there the compiler takes my word for it, which is why the 3.1 fix mattered.

Two known overhangs:

1. **`os.log` is the floor for the system engine.** ~820 ns is `os_log` itself. Beating it means losing `Console.app`.

2. **Engines are still classes.** `LogEngine` requires `AnyObject`: some engines need a long-lived identity, and the registry protects its default `SystemLogger` by `===`. That's one pointer load per engine in the fan-out.

The lesson is the one the JVM community learned twenty years ago: **the cheapest call is the one that doesn't run**, and you get there by making the filter the very first thing your call does. Everything else is plumbing.

→ Full benchmarks: [`PERFORMANCE.md`](../PERFORMANCE.md). Why the rewrite: [`01-why-rewrite.md`](01-why-rewrite.md).
