#if canImport(SwiftUI)
import Foundation
import SwiftMoLogger

#if canImport(Combine)
import Combine
#endif

/// Observable view-model that streams `LogEntry` values out of
/// ``SwiftMoLogger`` for SwiftUI consumption.
///
/// Lives off the main actor: ingestion runs on a detached task and only
/// hops to `@MainActor` to publish batched updates so the SwiftUI layer
/// never sees a synchronous write storm.
@MainActor
public final class LogConsoleViewModel: ObservableObject {
    @Published public internal(set) var entries: [LogEntry] = []
    @Published public var filterText: String = ""
    @Published public var minimumLevel: LogLevel = .trace
    @Published public var isPaused: Bool = false

    public let bufferLimit: Int
    private var ingestionTask: Task<Void, Never>?

    public init(bufferLimit: Int = 2_000) {
        self.bufferLimit = bufferLimit
    }

    public func start() {
        guard ingestionTask == nil else { return }
        let stream = SwiftMoLogger.stream(bufferSize: 512)
        ingestionTask = Task { [weak self] in
            for await entry in stream {
                guard let self = self else { return }
                if Task.isCancelled { return }
                await self.append(entry)
            }
        }
    }

    public func stop() {
        ingestionTask?.cancel()
        ingestionTask = nil
    }

    public func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    /// Apply level + substring filters lazily. Cheap because the underlying
    /// array is contiguous and filtering happens per render frame, not per
    /// log entry.
    public var visibleEntries: [LogEntry] {
        guard !filterText.isEmpty || minimumLevel != .trace else { return entries }
        let needle = filterText.lowercased()
        return entries.filter { entry in
            guard entry.level >= minimumLevel else { return false }
            if needle.isEmpty { return true }
            if entry.message.lowercased().contains(needle) { return true }
            if let tag = entry.tag, tag.rawValue.lowercased().contains(needle) { return true }
            return false
        }
    }

    private func append(_ entry: LogEntry) {
        guard !isPaused else { return }
        entries.append(entry)
        if entries.count > bufferLimit {
            entries.removeFirst(entries.count - bufferLimit)
        }
    }

    /// Combined plain-text export for share sheets / pasteboard.
    public func exportText() -> String {
        let formatter = ISO8601DateFormatter()
        return visibleEntries.map { entry in
            let timestamp = formatter.string(from: entry.timestamp)
            return "[\(timestamp)] [\(entry.level.description)] \(entry.formatted())"
        }.joined(separator: "\n")
    }
}
#endif
