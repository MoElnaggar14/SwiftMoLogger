import Foundation

/// Thread-safe registry that owns the list of active ``LogEngine`` instances
/// and dispatches every ``LogEntry`` to each of them.
///
/// There is no shared instance: create one (usually through
/// ``LogEnvironment``) at your composition root and inject it.
///
/// Implementation notes:
/// - Uses an unfair lock rather than a concurrent `DispatchQueue` because
///   reads dominate (one read per log call) and the critical section is tiny;
///   benchmarks show ~3× lower per-call cost than the old barrier queue.
/// - Holds engines in a `ContiguousArray` for predictable iteration cost.
/// - Ambient context is `@TaskLocal` (see ``LogContext``) so concurrent
///   `Task`s never trample each other's context.
public final class EngineRegistry: @unchecked Sendable {
    private var engines: ContiguousArray<any LogEngine> = []
    private let lock = UnfairLock()
    private var globalMinimumLevel: LogLevel = .trace
    /// The system logger installed by the registry itself. Protected from
    /// ``removeEngine(at:)`` / ``removeEngine(id:)`` by identity, so it stays
    /// protected wherever it sits in the list (and nothing else is protected
    /// by accident once it's gone).
    private var defaultSystemLogger: SystemLogger?
    /// Engines re-added by ``reset()`` (see ``addPersistentEngine(_:)``).
    private var persistentEngines: [any LogEngine] = []

    public init(installDefaultSystemLogger: Bool = true) {
        if installDefaultSystemLogger {
            let logger = SystemLogger()
            engines.append(logger)
            defaultSystemLogger = logger
        }
    }

    // MARK: - Engine management

    /// Add an engine. Idempotent by ``LogEngine/engineID``: re-adding an engine
    /// with the same id replaces the existing one rather than creating a
    /// duplicate.
    public func addEngine(_ engine: any LogEngine) {
        lock.lock()
        defer { lock.unlock() }
        if let index = engines.firstIndex(where: { $0.engineID == engine.engineID }) {
            if engines[index] === defaultSystemLogger { defaultSystemLogger = nil }
            engines[index] = engine
        } else {
            engines.append(engine)
        }
    }

    /// Remove the engine at the given index. The registry's default system
    /// logger is protected; use ``removeAllEngines()`` to drop it too.
    public func removeEngine(at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard engines.indices.contains(index), !isProtected(engines[index]) else { return }
        engines.remove(at: index)
    }

    /// Remove an engine by its stable ``LogEngine/engineID``. The registry's
    /// default system logger is protected.
    @discardableResult
    public func removeEngine(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = engines.firstIndex(where: { $0.engineID == id }), !isProtected(engines[index]) else {
            return false
        }
        engines.remove(at: index)
        return true
    }

    /// Atomically swap the engine with `id` for `transform(engine)`, keeping its
    /// position. No entry dispatched concurrently can miss both engines.
    ///
    /// `transform` runs under the registry lock: it must not log.
    ///
    /// - Returns: `false` if no engine has that id.
    @discardableResult
    public func replaceEngine(id: String, with transform: (any LogEngine) -> any LogEngine) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let index = engines.firstIndex(where: { $0.engineID == id }) else { return false }
        let replacement = transform(engines[index])
        if engines[index] === defaultSystemLogger { defaultSystemLogger = nil }
        engines[index] = replacement
        return true
    }

    private func isProtected(_ engine: any LogEngine) -> Bool {
        guard let defaultSystemLogger else { return false }
        return engine === defaultSystemLogger
    }

    /// Snapshot of all registered engines. Cheap (copies pointers only).
    public func allEngines() -> [any LogEngine] {
        lock.lock()
        defer { lock.unlock() }
        return Array(engines)
    }

    /// v2 compatibility alias.
    @available(*, deprecated, renamed: "allEngines()")
    public func getAllEngines() -> [any LogEngine] {
        allEngines()
    }

    public var engineCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return engines.count
    }

    /// Adds `engine` and keeps it across ``reset()``. ``LogEnvironment`` uses
    /// this for its stream, so subscribers stay connected through a reset.
    public func addPersistentEngine(_ engine: any LogEngine) {
        lock.lock()
        defer { lock.unlock() }
        persistentEngines.removeAll { $0.engineID == engine.engineID }
        persistentEngines.append(engine)
        if let index = engines.firstIndex(where: { $0.engineID == engine.engineID }) {
            engines[index] = engine
        } else {
            engines.append(engine)
        }
    }

    /// Back to a fresh state: the default system logger plus any persistent
    /// engines (such as a ``LogEnvironment``'s stream).
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        engines.removeAll(keepingCapacity: true)
        let logger = SystemLogger()
        engines.append(logger)
        engines.append(contentsOf: persistentEngines)
        defaultSystemLogger = logger
        globalMinimumLevel = .trace
    }

    /// Drop every engine, persistent ones included (``reset()`` brings those
    /// back). Mostly for tests; production code should prefer ``reset()``.
    public func removeAllEngines() {
        lock.lock()
        defer { lock.unlock() }
        engines.removeAll(keepingCapacity: true)
        defaultSystemLogger = nil
    }

    // MARK: - Global filtering

    /// Lowest level the registry accepts. Cheaper than per-engine filtering —
    /// entries below the threshold short-circuit before any allocation.
    public var minimumLevel: LogLevel {
        get {
            lock.lock()
            defer { lock.unlock() }
            return globalMinimumLevel
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            globalMinimumLevel = newValue
        }
    }

    // MARK: - Dispatch

    /// Hot path. Branches early on level, snapshots engines under the lock,
    /// then dispatches without holding it so an engine performing slow I/O
    /// cannot block writers. The ambient ``LogContext`` is merged in here.
    public func dispatch(_ entry: LogEntry) {
        lock.lock()
        let level = globalMinimumLevel
        guard entry.level >= level else {
            lock.unlock()
            return
        }
        let snapshot = engines
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
}
