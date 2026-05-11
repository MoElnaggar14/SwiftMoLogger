import Foundation
import SwiftMoLogger

/// Test-only engine that records every entry for later assertions.
///
/// Replace the default ``SystemLogger`` with a `RecordingLogEngine` in
/// `setUp` to drive XCTest assertions about *what* the system under test
/// logged.
public final class RecordingLogEngine: LogEngine, @unchecked Sendable {
    public let engineID: String = "swiftmologger.testing.recording"
    public let minimumLevel: LogLevel = .trace

    private var lock = os_unfair_lock_s()
    private var entries: [LogEntry] = []

    public init() {}

    public func log(_ entry: LogEntry) {
        os_unfair_lock_lock(&lock)
        entries.append(entry)
        os_unfair_lock_unlock(&lock)
    }

    public func recorded() -> [LogEntry] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return entries
    }

    public func clear() {
        os_unfair_lock_lock(&lock)
        entries.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&lock)
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
