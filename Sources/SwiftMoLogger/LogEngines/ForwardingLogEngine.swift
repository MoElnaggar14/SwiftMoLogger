import Foundation

/// Hands entries to a closure: the bridge to SDKs SwiftMoLogger doesn't depend on,
/// such as Firebase Crashlytics, Bugsnag, Embrace or an analytics SDK.
///
/// SwiftMoLogger ships no vendor SDKs: SwiftPM would download them for every app
/// that depends on the package. With this engine the app keeps the SDK dependency
/// and the bridge is a few lines:
///
/// ```swift
/// import FirebaseCrashlytics
///
/// // Crashlytics attaches recent log lines to the next crash report.
/// let crashlytics = ForwardingLogEngine(minimumLevel: .info) { entry in
///     Crashlytics.crashlytics().log(entry.formatted())
/// }
/// logging.registry.addEngine(RedactingLogEngine(wrapping: crashlytics))
/// ```
///
/// Use `where:` to forward only some entries, for example business events to an
/// analytics SDK:
///
/// ```swift
/// ForwardingLogEngine(where: { $0.tag?.domain.hasPrefix("business") == true }) { entry in
///     Analytics.track(entry.message, properties: entry.metadata.storage.mapValues(\.description))
/// }
/// ```
///
/// The closures run on the logging thread, so keep them cheap: hand off to the SDK,
/// which usually queues internally. Wrap the engine in ``RedactingLogEngine`` before
/// anything leaves the device.
public final class ForwardingLogEngine: LogEngine {
    public let engineID: String
    public let minimumLevel: LogLevel

    private let filter: @Sendable (LogEntry) -> Bool
    private let forward: @Sendable (LogEntry) -> Void
    private let onFlush: (@Sendable () -> Void)?

    /// - Parameters:
    ///   - id: A stable ID, so adding a second engine with the same ID replaces the first.
    ///     Defaults to a new ID per instance.
    ///   - minimumLevel: Entries below this level never reach `filter` or `forward`.
    ///   - filter: Forwards an entry only when this returns `true`.
    ///   - flush: Called by ``EngineRegistry/flush()``, e.g. to make the SDK send now.
    ///   - forward: Receives each entry that passes the level and the filter.
    public init(
        id: String? = nil,
        minimumLevel: LogLevel = .trace,
        where filter: @escaping @Sendable (LogEntry) -> Bool = { _ in true },
        flush: (@Sendable () -> Void)? = nil,
        forward: @escaping @Sendable (LogEntry) -> Void
    ) {
        self.engineID = id ?? "swiftmologger.forwarding.\(UUID().uuidString)"
        self.minimumLevel = minimumLevel
        self.filter = filter
        self.onFlush = flush
        self.forward = forward
    }

    public func log(_ entry: LogEntry) {
        // The registry already skips entries below minimumLevel; this keeps direct calls honest.
        guard entry.level >= minimumLevel, filter(entry) else { return }
        forward(entry)
    }

    public func flush() {
        onFlush?()
    }
}
