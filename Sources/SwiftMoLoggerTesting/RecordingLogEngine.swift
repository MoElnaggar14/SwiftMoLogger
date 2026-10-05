import Foundation
// Re-exported so `import SwiftMoLoggerTesting` alone gives tests MoLogger and LogEnvironment.
@_exported import SwiftMoLogger

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

    // MARK: - Queries

    /// Recorded entries matching every condition you pass (`nil` matches anything).
    /// Tags match by domain, so `.api` matches entries tagged `.Network.api`.
    ///
    /// These return plain values, so they work with any test framework:
    ///
    /// ```swift
    /// #expect(logs.contains(.error, containing: "declined", tag: .api))   // Swift Testing
    /// XCTAssertEqual(logs.count(.warning), 0)                             // XCTest
    /// ```
    public func entries(
        _ level: LogLevel? = nil,
        containing substring: String? = nil,
        tag: LogTag? = nil,
        withMetadataKey key: String? = nil
    ) -> [LogEntry] {
        recorded().filter { entry in
            if let level, entry.level != level { return false }
            if let substring, !entry.message.contains(substring) { return false }
            if let tag, entry.tag?.domain != tag.domain { return false }
            if let key, entry.metadata[key] == nil { return false }
            return true
        }
    }

    /// Whether any recorded entry matches every condition you pass.
    public func contains(
        _ level: LogLevel? = nil,
        containing substring: String? = nil,
        tag: LogTag? = nil,
        withMetadataKey key: String? = nil
    ) -> Bool {
        !entries(level, containing: substring, tag: tag, withMetadataKey: key).isEmpty
    }

    /// How many recorded entries match every condition you pass.
    public func count(
        _ level: LogLevel? = nil,
        containing substring: String? = nil,
        tag: LogTag? = nil,
        withMetadataKey key: String? = nil
    ) -> Int {
        entries(level, containing: substring, tag: tag, withMetadataKey: key).count
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
    /// #expect(logs.contains(.info, containing: "Paying"))   // or with Swift Testing
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
