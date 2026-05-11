import SwiftUI
import SwiftMoLogger

/// Minimal observable view model — polls the in-process stores on a tick
/// so the Demo tab can show live counters. The Hub tab is self-driving and
/// doesn't go through here.
@MainActor
final class LoggingDemoViewModel: ObservableObject {
    @Published var memoryCounters: (total: Int, warnings: Int, errors: Int) = (0, 0, 0)
    @Published var breadcrumbCount: Int = 0

    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                await MainActor.run { self.refresh() }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func clearAll() {
        SwiftMoLogger.clearBreadcrumbs()
        for engine in SwiftMoLogger.allEngines() {
            if let memory = engine as? MemoryLogEngine {
                memory.clear()
            }
        }
        refresh()
    }

    private func refresh() {
        for engine in SwiftMoLogger.allEngines() {
            if let memory = engine as? MemoryLogEngine {
                memoryCounters = memory.counters()
                break
            }
        }
        breadcrumbCount = SwiftMoLogger.breadcrumbs().count
    }
}
