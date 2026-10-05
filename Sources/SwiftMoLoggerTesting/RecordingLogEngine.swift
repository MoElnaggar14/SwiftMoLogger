import Foundation
import SwiftMoLogger

/// Test-only engine that records every entry for later assertions.
///
/// Inject a logger from ``LogEnvironment/recording()`` or
/// ``MoLogger/recording()`` into the system under test, then assert on
/// *what* it logged.
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

public extension LogEnvironment {
    /// A fresh environment whose only engine (besides its stream) is a
    /// ``RecordingLogEngine``. Nothing global is touched, so tests using it
    /// can run in parallel.
    ///
    /// ```swift
    /// let (logging, logs) = LogEnvironment.recording()
    /// let service = CheckoutService(log: logging.logger)
    /// service.pay(orderID: "42")
    /// XCTAssertLogged(.info, contains: "Paying", in: logs)
    /// ```
    static func recording() -> (environment: LogEnvironment, recorder: RecordingLogEngine) {
        let environment = LogEnvironment(registry: EngineRegistry(installDefaultSystemLogger: false))
        let recorder = RecordingLogEngine()
        environment.registry.addEngine(recorder)
        return (environment, recorder)
    }
}

public extension MoLogger {
    /// A logger bound to its own registry, plus the recorder capturing its entries.
    static func recording() -> (logger: MoLogger, recorder: RecordingLogEngine) {
        let (environment, recorder) = LogEnvironment.recording()
        return (environment.logger, recorder)
    }
}
