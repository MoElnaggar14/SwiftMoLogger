#if canImport(SwiftUI)
import Foundation
import SwiftUI
import SwiftMoLogger

/// Drives ``DiagnosticsHubView``. Reads the stores of the ``LogEnvironment``
/// it's given (plus its own `MemoryLogEngine` for logs) and exposes a unified
/// "scrubbed time" so every sub-view stays in lockstep with the timeline.
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
public final class HubViewModel: ObservableObject {
    public enum Tab: String, Sendable, CaseIterable, Identifiable {
        case logs
        case network
        case signposts
        case vitals
        case breadcrumbs
        public var id: String { rawValue }
        public var title: String { rawValue.capitalized }
        public var icon: String {
            switch self {
            case .logs: return "text.alignleft"
            case .network: return "network"
            case .signposts: return "waveform.path.ecg"
            case .vitals: return "heart.text.square"
            case .breadcrumbs: return "fossil.shell"
            }
        }
    }

    @Published public var selectedTab: Tab = .logs
    @Published public var entries: [LogEntry] = []
    @Published public var networkEvents: [NetworkEvent] = []
    @Published public var signpostEvents: [SignpostEvent] = []
    @Published public var vitalsHistory: [VitalsTick] = []
    @Published public var breadcrumbs: [Breadcrumb] = []

    /// Live (`nil`) by default. When the user starts scrubbing the timeline,
    /// this becomes the end of the visible window and sub-views filter
    /// against `[windowStart, scrubbedTime]`.
    @Published public var scrubbedTime: Date?
    @Published public var windowDuration: TimeInterval = 60

    public let environment: LogEnvironment
    public let memoryEngine: MemoryLogEngine
    private let refreshInterval: TimeInterval
    private var task: Task<Void, Never>?

    /// - Parameters:
    ///   - environment: Whose registry and stores the Hub shows.
    ///   - memoryEngine: Retains recent entries for the Logs tab; registered with the environment.
    public init(
        environment: LogEnvironment,
        memoryEngine: MemoryLogEngine = MemoryLogEngine(capacity: 2_000),
        refreshInterval: TimeInterval = 0.5
    ) {
        self.environment = environment
        self.memoryEngine = memoryEngine
        self.refreshInterval = refreshInterval
        environment.registry.addEngine(memoryEngine)
    }

    public func start() {
        guard task == nil else { return }
        let interval = refreshInterval
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                await MainActor.run { self.refresh() }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func refresh() {
        entries = memoryEngine.snapshot()
        networkEvents = environment.networkEvents.snapshot()
        signpostEvents = environment.signposts.snapshot()
        vitalsHistory = environment.vitals.snapshot()
        breadcrumbs = environment.breadcrumbs.snapshot()
    }

    public func clearAll() {
        memoryEngine.clear()
        environment.networkEvents.clear()
        environment.signposts.clear()
        environment.vitals.clear()
        environment.breadcrumbs.clear()
        refresh()
    }

    // MARK: - Window helpers

    public var windowEnd: Date {
        scrubbedTime ?? Date()
    }

    public var windowStart: Date {
        windowEnd.addingTimeInterval(-windowDuration)
    }

    public func inWindow(_ timestamp: Date) -> Bool {
        timestamp >= windowStart && timestamp <= windowEnd
    }
}
#endif
