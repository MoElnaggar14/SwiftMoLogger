# Sub-µs logging: the performance design

> "Logging is fine, it doesn't show up in profiles." — every team, ten seconds before logging shows up in profiles.

The first version of SwiftMoLogger v2 used a concurrent `DispatchQueue` with barrier writes to protect its engine list. The second version inlined a copy of the engine array into every log call. Both worked. Neither was fast enough to log in a tight Metal render loop without showing up on a trace.

[PERFORMANCE.md](../PERFORMANCE.md) puts a log call with no engines attached at ~140 ns. This is the article on how it got there. In 4.0 there's no static facade any more: every call goes through a `MoLogger` you inject from a `LogEnvironment`.

## What "fast" means for a logger

The hot path is what runs *every time* you call `logger.info("…")`, whether the entry is kept, dropped, or fanned out. I care about four budgets:

1. **CPU time.** How many nanoseconds.
2. **Allocations.** How many heap objects materialise.
3. **Lock contention.** What blocks other threads.
4. **Argument evaluation.** Whether `"\(complexExpression())"` runs even when filtered.

A fast logger is one where dropping a call below the minimum level costs a level check and little else: no string interpolation, no `Date()`, no `LogEntry`.

## The lock that isn't a queue

v2 used:

```swift
let queue = DispatchQueue(label: "registry", qos: .utility, attributes: .concurrent)

func allEngines() -> [LogEngine] {
    queue.sync { Array(engines) }
}
```

A `sync` hop is much heavier than an uncontended lock, and `Array(engines)` allocates. **Every log call paid that.**

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

The critical section is one comparison and one array copy. Copying a `ContiguousArray` only retains its buffer, and copy-on-write means a later `addEngine` builds a new buffer instead of touching the one we're iterating. Think of a bouncer with a photo of the guest list: he checks your name at the door, then goes back to his post. He doesn't walk you to the bar. Fan-out happens **outside** the lock, so a slow engine can't stall the next caller.

The registry's own notes credit this design with ~3× lower per-call cost than the old barrier queue.

### The 3.1 fix: a lock needs an address

v3 stored the lock as `private var lock = os_unfair_lock_s()` and called `os_unfair_lock_lock(&lock)`. That looks right, and it's undefined behaviour. `&` on a stored Swift property doesn't promise a stable address; the compiler may hand over a pointer to a temporary copy. Two threads can then lock two different copies, and the lock silently does nothing. It's like agreeing to meet "at the whiteboard" when everyone was handed their own photocopy of it.

Thirteen types had this pattern. 3.1 replaced all of them with a small heap-allocated wrapper (`Core/UnfairLock.swift`, abridged):

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

The lock is allocated once, with its owner, and never moves. The hot path allocates nothing for it.

## Filtering before allocation

In 3.0 the level helpers looked like this:

```swift
public static func info(_ message: @autoclosure () -> String, …) {
    log(.info, message(), …)   // evaluates message() here
}
```

The `@autoclosure` was decorative: `info` called `message()` to hand a `String` to `log()`, so `info("user \(expensiveDescribe(user))")` did the expensive work even when the entry was dropped.

In 4.0, `MoLogger.info` passes `message()` into `log`'s own `@autoclosure` parameter, so nothing runs yet. `MoLogger.log` checks the level first (abridged):

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

The message, `UUID()`, `Date()`, the thread name and the `LogEntry` are only built once the entry passes. Reading `minimumLevel` takes the registry's lock, so a filtered call is one short lock round trip; a kept call takes it twice (here and in `dispatch`).

Two honest caveats:

- **`metadata` is not lazy.** It's a plain parameter, evaluated at the call site *before* the level check. So is the metadata the `error(_ error: any Error)` overload builds. If a metadata value is expensive, put it in the message or check the level yourself.
- **`debug` is compiled out of release builds** (`#if DEBUG` inside its body), so its message never runs there. Its arguments, metadata included, still do.

In production, set the level once at the composition root:

```swift
let logging = LogEnvironment()
logging.registry.minimumLevel = .info
logging.registry.addEngine(MemoryLogEngine(capacity: 500))

let log = logging.logger.with(tag: .api)
let payload = Data(count: 4_096)
log.trace("payload: \(payload.base64EncodedString())")   // never encoded at .info
```

## The shape of `LogEntry`

A few `LogEntry` choices matter for speed:

- It's a struct with `let` fields, so there's no reference counting of the entry itself.
- `SourceLocation` comes from compile-time literals (`#fileID`, `#function`, `#line`, `#column`). No backtrace walk, no symbolication.
- The thread name checks `Thread.isMainThread` first and falls back to `Thread.current.name`, avoiding `Thread.current.description`, which allocates.

PERFORMANCE.md lists `LogEntry` at 200 B on the stack, with no heap traffic unless `metadata` is non-empty (a long message string allocates on its own). In 4.0, two things add a dictionary merge per kept call: a child logger made with `with(metadata:)`, and an ambient `LogContext`. Usually fine; not free.

## What the numbers look like

From [PERFORMANCE.md](../PERFORMANCE.md): release build, M1 MacBook Pro, iOS 17 simulator, measured by `Tests/SwiftMoLoggerTests/PerformanceBenchmarks.swift`:

| Scenario | per-call median | per-call p99 |
|---|---|---|
| `info("…")` — no engines | **~140 ns** | ~220 ns |
| `info("…")` — `MemoryLogEngine` only | **~310 ns** | ~460 ns |
| `info("…")` filtered by `minimumLevel = .error` | **~35 ns** | ~60 ns |
| `info("…")` — `SystemLogger` (os.log) only | **~820 ns** | ~1.3 µs |
| Concurrent 8 threads × 2 000 calls | **~22 ms total** | linear scaling |

The filtered case matters most. Most apps run at `.info` with hundreds of `trace` call sites in the codebase. Those cost a level check and a return. You can leave them in.

`FileLogEngine.log(_:)` only enqueues the entry on a private serial queue (~80 ns per PERFORMANCE.md); encoding and disk writes happen off your thread.

## The Flight Recorder's bill

The Flight Recorder runs in production, so it has to fit the budget. On the hot path it's a `MemoryLogEngine` (capacity 1,000 by default): one append under a lock. Disk work happens on a timer, on a background queue.

In 3.0 that timer rewrote the file every 2 seconds, even when idle, enough to trigger iOS disk-write warnings. Since 3.1 it remembers the newest item of each source and skips the encode and the write when nothing changed. The default interval is now 5 seconds, plus a flush when the app goes to the background:

```swift
let recorder = FlightRecorder(environment: logging)   // flushInterval defaults to 5
recorder.start()
```

## Swift 6, and what I'd still like to improve

4.0's library targets compile in the Swift 6 language mode with full data-race checking. `MoLogger` and `LogEnvironment` are `Sendable` structs, so handing a logger to a task or actor is cheap and compiler-checked. The engines are `@unchecked Sendable` classes that keep any mutable state behind an `UnfairLock` or a serial queue. That's where the compiler takes my word for it, which is why the 3.1 lock fix mattered.

Two known overhangs:

1. **`os.log` is the floor for the system engine.** ~820 ns isn't us; it's `os_log` formatting and routing through `logd`. Beating it means losing `Console.app`. The tradeoff is right.

2. **Engines are still classes.** `LogEngine` requires `AnyObject`: `FileLogEngine` and `LiveSink` need a long-lived identity for their worker queues, and the registry protects its default `SystemLogger` by identity (`===`). That's one pointer load per engine in the fan-out loop. 4.0 kept it.

The lesson is the one the JVM community learned about logging twenty years ago: **the cheapest call is the one that doesn't run**, and you get there by making the filter the very first thing your call does. Everything else is plumbing.

→ See [`PERFORMANCE.md`](../PERFORMANCE.md) for the full benchmark table, and [`01-why-rewrite.md`](01-why-rewrite.md) for why the rewrite happened at all.
