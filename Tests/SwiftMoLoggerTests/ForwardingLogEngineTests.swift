import Foundation
import SwiftMoLogger
import Testing

/// Collects forwarded values across threads.
// @unchecked Sendable: every access goes through the lock.
private final class Collected<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    var values: [Value] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Value) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

@Suite("Forwarding engine")
struct ForwardingLogEngineTests {
    private func makeRegistry(with engine: ForwardingLogEngine) -> EngineRegistry {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        registry.addEngine(engine)
        return registry
    }

    @Test func forwardsEntriesAtOrAboveItsLevel() {
        let messages = Collected<String>()
        let registry = makeRegistry(with: ForwardingLogEngine(minimumLevel: .warning) { messages.append($0.message) })

        registry.dispatch(LogEntry(level: .info, message: "quiet"))
        registry.dispatch(LogEntry(level: .warning, message: "loud"))
        registry.dispatch(LogEntry(level: .error, message: "louder"))

        #expect(messages.values == ["loud", "louder"])
    }

    @Test func filterSelectsWhichEntriesAreForwarded() {
        let messages = Collected<String>()
        let engine = ForwardingLogEngine(where: { $0.tag == .api }) { messages.append($0.message) }
        let registry = makeRegistry(with: engine)

        registry.dispatch(LogEntry(level: .info, message: "kept", tag: .api))
        registry.dispatch(LogEntry(level: .info, message: "dropped"))

        #expect(messages.values == ["kept"])
    }

    @Test func directCallsRespectTheMinimumLevel() {
        let messages = Collected<String>()
        let engine = ForwardingLogEngine(minimumLevel: .error) { messages.append($0.message) }

        engine.log(LogEntry(level: .debug, message: "below"))

        #expect(messages.values.isEmpty)
    }

    @Test func registryFlushReachesTheFlushClosure() {
        let flushes = Collected<Void>()
        let registry = makeRegistry(with: ForwardingLogEngine(flush: { flushes.append(()) }) { _ in })

        registry.flush()

        #expect(flushes.values.count == 1)
    }

    @Test func stableIDReplacesInsteadOfDuplicating() {
        let first = Collected<String>()
        let second = Collected<String>()
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        registry.addEngine(ForwardingLogEngine(id: "crashlytics") { first.append($0.message) })
        registry.addEngine(ForwardingLogEngine(id: "crashlytics") { second.append($0.message) })

        registry.dispatch(LogEntry(level: .info, message: "once"))

        #expect(first.values.isEmpty)
        #expect(second.values == ["once"])
    }

    @Test func defaultIDsKeepSeparateEnginesRegistered() {
        let messages = Collected<String>()
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        registry.addEngine(ForwardingLogEngine { messages.append("a:" + $0.message) })
        registry.addEngine(ForwardingLogEngine { messages.append("b:" + $0.message) })

        registry.dispatch(LogEntry(level: .info, message: "x"))

        #expect(Set(messages.values) == ["a:x", "b:x"])
    }
}
