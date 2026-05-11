# Sub-µs logging: the performance design

> "Logging is fine, it doesn't show up in profiles." — every team, ten seconds before logging shows up in profiles.

The first version of SwiftMoLogger v2 used a concurrent `DispatchQueue` with barrier writes to protect its engine list. The second version inlined a copy of the engine array into every log call. Both worked. Neither was fast enough to log in a tight Metal render loop without showing up on a trace.

v3 hits ~140 ns for a log call when no engines are attached. This is the article on how it got there.

## What "fast" means for a logger

The hot path of a log call is the sequence of instructions that run *every time* you call `info("…")`, regardless of whether the entry is kept, dropped, or fanned out. There are four budgets we care about:

1. **CPU time.** How many nanoseconds.
2. **Allocations.** How many heap objects materialised.
3. **Lock contention.** What blocks other threads.
4. **Argument evaluation.** Whether `"\(complexExpression())"` runs even when filtered.

A "fast" logger is one where dropping a call below `minimumLevel` costs you a level comparison and nothing else — no string interpolation, no `Date()`, no `Array` allocation.

## The lock that isn't a queue

v2 used:

```swift
let queue = DispatchQueue(label: "registry", qos: .utility, attributes: .concurrent)

func allEngines() -> [LogEngine] {
    queue.sync { Array(engines) }
}
```

That `sync` hop costs ~300 ns even when the queue is uncontended, and `Array(engines)` allocates. **Every log call paid that.**

v3 uses `os_unfair_lock`:

```swift
private var lock = os_unfair_lock_s()

public func dispatch(_ entry: LogEntry) {
    os_unfair_lock_lock(&lock)
    let level = globalMinimumLevel
    guard entry.level >= level else {
        os_unfair_lock_unlock(&lock)
        return
    }
    let snapshot = engines      // copy of ContiguousArray<any LogEngine>
    os_unfair_lock_unlock(&lock)

    for engine in snapshot where entry.level >= engine.minimumLevel {
        engine.log(entry)
    }
}
```

`os_unfair_lock_lock` is ~10 ns uncontended. The critical section is one comparison and one array copy. The `ContiguousArray` of class references is essentially a pointer copy — no heap traffic. The engines fan-out happens **outside** the lock, so a slow I/O engine can't stall the next call.

This single change dropped per-call cost ~3×.

## Filtering before allocation

The level helpers used to look like this:

```swift
public static func info(_ message: @autoclosure () -> String, …) {
    log(.info, message(), …)   // evaluates message() here
}
```

The `@autoclosure` was decorative: `info` called `message()` to pass a `String` to `log()`, which made the lazy wrapping pointless. If your call was `info("user \(expensiveDescribe(user))")`, the expensive computation ran whether or not the entry was kept.

The fix is a single line:

```swift
public static func info(_ message: @autoclosure () -> String, …) {
    guard LogLevel.info >= EngineRegistry.shared.minimumLevel else { return }
    log(.info, message(), …)
}
```

Now the autoclosure only runs when the entry survives the global filter. Setting `minimumLevel = .warning` in production drops trace/debug/info to ~35 ns and zero allocations — even if your call site does heavy interpolation.

## The shape of `LogEntry`

Several `LogEntry` design choices have direct perf impact:

- `Sendable, Hashable, Codable, Identifiable` — all marker protocols, no vtable cost.
- All fields are `let` — copy-on-write applies only to `metadata.storage`'s underlying `Dictionary`. For empty metadata, the dictionary header is shared.
- `SourceLocation` is captured via compile-time literals (`#fileID`, `#function`, `#line`). No backtrace walk, no symbolication.
- `threadName` checks `Thread.isMainThread` first (a single CPU instruction) before falling back to `Thread.current.name`. We deliberately avoided `Thread.current.description`, which allocates.

`LogEntry` is 200 bytes on the stack. The only heap traffic per call is the metadata dictionary, and only if the caller passes a non-empty metadata bag.

## What the numbers look like

Measured on an M1 MacBook Pro, iOS 17 simulator, release build, in the benchmark target shipped with the package:

| Scenario | per-call median | per-call p99 |
|---|---|---|
| `info("…")` — no engines | **~140 ns** | ~220 ns |
| `info("…")` — `MemoryLogEngine` only | **~310 ns** | ~460 ns |
| `info("…")` filtered by `minimumLevel` | **~35 ns** | ~60 ns |
| `info("…")` — `SystemLogger` (os.log) | **~820 ns** | ~1.3 µs |
| Concurrent 8 threads × 2 000 calls | **~22 ms total** | linear scaling |

The filtered case is the most important one. Most production apps set `minimumLevel = .info` and have hundreds of `trace`/`debug` call sites peppered through their codebase. Those calls cost essentially nothing — a level comparison and a return. You can leave them in.

## What I'd still like to improve

Two known overhangs:

1. **`os.log` is the floor for the system engine.** ~820 ns isn't us; it's `os_log` itself doing the formatting and routing through `logd`. We can't beat it without skipping `os_log`, which sacrifices `Console.app` integration. The tradeoff is correct as it stands.

2. **Sendable + class-conforming engines.** `LogEngine` requires `AnyObject` because some engines (`FileLogEngine`, `LiveSink`) need a long-lived identity for the worker queue. The class indirection is one extra pointer load per engine in the fan-out loop. Switching to a `Sendable` struct-based protocol would save it but lose those engines. Worth it for v4, probably not v3.

The lesson, again, is the lesson the JVM community learned about logging twenty years ago: **the cheapest call is the one that doesn't run**, and the way you get there is by making the filter the very first thing your call does. Everything else is plumbing.

→ See [`PERFORMANCE.md`](../PERFORMANCE.md) for the full benchmark table and the design notes that drove each number.
