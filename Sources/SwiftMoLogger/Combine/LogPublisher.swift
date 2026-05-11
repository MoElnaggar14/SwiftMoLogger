#if canImport(Combine)
import Combine
import Foundation

/// Combine publisher alongside the `AsyncStream` API.
///
/// Use this when integrating with a Combine codebase. Internally this is a
/// `PassthroughSubject` wrapped by a custom ``LogEngine`` that fans entries
/// into it; subscribing more than once adds more subscribers, not more
/// engines.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class CombineLogPublisher: LogEngine, @unchecked Sendable {
    public static let shared = CombineLogPublisher()

    public let engineID: String = "swiftmologger.combine"
    public let minimumLevel: LogLevel = .trace

    private let subject = PassthroughSubject<LogEntry, Never>()

    public var publisher: AnyPublisher<LogEntry, Never> {
        subject.eraseToAnyPublisher()
    }

    public func log(_ entry: LogEntry) {
        subject.send(entry)
    }
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension SwiftMoLogger {
    /// Combine publisher of every entry passing through the registry.
    /// Registers the publisher engine on first use.
    static func publisher() -> AnyPublisher<LogEntry, Never> {
        let id = CombineLogPublisher.shared.engineID
        if !EngineRegistry.shared.allEngines().contains(where: { $0.engineID == id }) {
            EngineRegistry.shared.addEngine(CombineLogPublisher.shared)
        }
        return CombineLogPublisher.shared.publisher
    }
}
#endif
