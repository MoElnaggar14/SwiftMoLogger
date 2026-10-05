#if canImport(Combine)
import Combine
import Foundation

/// Combine publisher alongside the `AsyncStream` API.
///
/// Use this when integrating with a Combine codebase. Add an instance to your
/// registry, then subscribe to ``publisher``:
///
/// ```swift
/// let combine = CombineLogPublisher()
/// environment.registry.addEngine(combine)
/// combine.publisher.filter { $0.level >= .error }.sink { … }
/// ```
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public final class CombineLogPublisher: LogEngine, @unchecked Sendable {
    public let engineID = "swiftmologger.combine.\(UUID().uuidString)"
    public let minimumLevel: LogLevel = .trace

    private let subject = PassthroughSubject<LogEntry, Never>()

    public init() {}

    public var publisher: AnyPublisher<LogEntry, Never> {
        subject.eraseToAnyPublisher()
    }

    public func log(_ entry: LogEntry) {
        subject.send(entry)
    }
}
#endif
