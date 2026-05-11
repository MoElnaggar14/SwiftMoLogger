import SwiftUI
import SwiftMoLogger
import SwiftMoLoggerDiagnostics

@MainActor
final class LoggingDemoViewModel: ObservableObject {
    @Published var memoryCounters: (total: Int, warnings: Int, errors: Int) = (0, 0, 0)
    @Published var breadcrumbCount: Int = 0
    @Published var lastVitals: AppVitalsMonitor.Sample?

    let bugReporter: BugReporter

    private var liveSink: LiveSink?
    private var task: Task<Void, Never>?

    init() {
        let memory = SwiftMoLogger.allEngines().compactMap { $0 as? MemoryLogEngine }.first
        self.bugReporter = BugReporter(memoryEngine: memory, appName: "SwiftMoLoggerExample")
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.refresh() }
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
            if let memory = engine as? MemoryLogEngine { memory.clear() }
            if let grouping = engine as? ErrorGroupingEngine { grouping.clear() }
        }
        refresh()
    }

    func fetch(_ url: URL) async -> String {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            return "\(status) · \(data.count) B"
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    func startLiveSink() {
        guard liveSink == nil else { return }
        let sink = LiveSink()
        do {
            try sink.start()
            SwiftMoLogger.addEngine(sink)
            liveSink = sink
            SwiftMoLogger.notice("LiveSink advertising on Bonjour", tag: .Development.debug)
        } catch {
            SwiftMoLogger.error(error, tag: .Development.debug)
        }
    }

    func stopLiveSink() {
        guard let sink = liveSink else { return }
        sink.stop()
        _ = SwiftMoLogger.removeEngine(id: sink.engineID)
        liveSink = nil
    }

    private func refresh() {
        for engine in SwiftMoLogger.allEngines() {
            if let memory = engine as? MemoryLogEngine {
                memoryCounters = memory.counters()
                break
            }
        }
        breadcrumbCount = SwiftMoLogger.breadcrumbs().count
        lastVitals = AppVitalsMonitor.shared.lastSample
    }
}
