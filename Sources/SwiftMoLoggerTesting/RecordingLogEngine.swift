import Foundation
import SwiftMoLogger

/// Test-only engine that records every entry for later assertions.
///
/// Replace the default ``SystemLogger`` with a `RecordingLogEngine` in
/// `setUp` to drive XCTest assertions about *what* the system under test
/// logged.
public final class RecordingLogEngine: LogEngine, @unchecked Sendable {
    public let engineID = "swiftmologger.testing.recording.\(UUID().uuidString)"
    public let minimumLevel: LogLevel = .trace

    private let lock = UnfairLock()
    private var entries: [LogEntry] = []

    public init() {}

    public func log(_ entry: LogEntry) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    public func recorded() -> [LogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    public func clear() {
        lock.lock()
        entries.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

public extension SwiftMoLogger {
    /// One-shot helper for tests: replaces all registered engines with a
    /// fresh ``RecordingLogEngine`` and returns it.
    static func installRecorder() -> RecordingLogEngine {
        let recorder = RecordingLogEngine()
        EngineRegistry.shared.removeAllEngines()
        EngineRegistry.shared.addEngine(recorder)
        return recorder
    }
}
