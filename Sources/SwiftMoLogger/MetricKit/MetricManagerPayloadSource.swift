import Foundation

// `MetricManager` ships in the iOS 27 / macOS 27 SDK (Xcode 27, Swift 6.4).
// Its daily metric reports aren't delivered on visionOS, and the reporter only
// exists on iOS and macOS, so the source follows the same platforms.
#if compiler(>=6.4) && canImport(MetricKit) && (os(iOS) || os(macOS))
import MetricKit

/// The ``MetricPayloadSource`` that reads the iOS 27 `MetricManager` API.
///
/// ``MetricKitCrashReporter/init(logger:)`` uses it on iOS 27 and macOS 27,
/// unless a crash or hang delegate is set before monitoring starts.
/// `MetricManager` delivers typed `MetricReport` and `DiagnosticReport` values
/// through async sequences instead of `jsonRepresentation()`, so the source
/// writes the values the summaries read into the same JSON shape. The reporter
/// logs the same entries as with `MXMetricManagerPayloadSource`.
///
/// Each diagnostic report holds one event, so it's delivered as its own payload.
/// Memory-exception diagnostics, and report kinds added after iOS 27, aren't logged.
///
/// Apple recommends creating one `MetricManager` at launch and sharing it:
/// pass yours to ``init(manager:)`` if the app reads reports elsewhere too.
@available(iOS 27, macOS 27, *)
public final class MetricManagerPayloadSource: MetricPayloadSource, @unchecked Sendable {
    // @unchecked Sendable: `handler` and `tasks` are only read and written while
    // holding `lock`, and `manager` is an immutable `Sendable` reference.
    private let manager: MetricManager
    private let lock = UnfairLock()
    private var handler: (@Sendable ([MetricKitPayload]) -> Void)?
    private var tasks: [Task<Void, Never>] = []

    /// Reads reports from `manager`.
    public init(manager: MetricManager) {
        self.manager = manager
    }

    /// Reads reports from a new `MetricManager`.
    public convenience init() {
        self.init(manager: MetricManager())
    }

    deinit {
        for task in tasks {
            task.cancel()
        }
    }

    /// Starts iterating the manager's report sequences, once. Iteration keeps
    /// going after ``stop()``, because two tasks iterating the same sequence
    /// would each get only some of the reports; reports that arrive while
    /// stopped are dropped.
    public func start(delivering handler: @escaping @Sendable ([MetricKitPayload]) -> Void) {
        lock.withLock {
            self.handler = handler
            guard tasks.isEmpty else { return }
            let manager = self.manager
            tasks = [
                Task { [weak self] in
                    for await report in manager.metricReports {
                        self?.deliver(MetricReportValues(report).payload)
                    }
                },
                Task { [weak self] in
                    for await report in manager.diagnosticReports {
                        guard let values = DiagnosticReportValues(report) else { continue }
                        self?.deliver(values.payload)
                    }
                }
            ]
        }
    }

    public func stop() {
        lock.withLock { handler = nil }
    }

    private func deliver(_ payload: MetricKitPayload) {
        guard let current = lock.withLock({ self.handler }) else { return }
        current([payload])
    }
}

// MARK: - Reading reports

@available(iOS 27, macOS 27, *)
extension MetricKitReportMetadata {
    init(_ environment: MetricReport.Environment) {
        self.init(
            appVersion: environment.latestApplicationVersion,
            appBuildVersion: environment.applicationBuildVersion,
            osVersion: Self.string(environment.osVersion),
            deviceType: environment.deviceType,
            platformArchitecture: environment.platformArchitecture,
            bundleIdentifier: environment.bundleIdentifier
        )
    }

    init(_ environment: DiagnosticReport.Environment) {
        self.init(
            appVersion: environment.applicationVersion,
            appBuildVersion: environment.applicationBuildVersion,
            osVersion: Self.string(environment.osVersion),
            deviceType: environment.deviceType,
            platformArchitecture: environment.platformArchitecture,
            bundleIdentifier: environment.bundleIdentifier
        )
    }

    /// `iOS 27.0 (24A5300a)`.
    private static func string(_ version: OSVersion) -> String {
        "\(version.platform) \(version.number) (\(version.buildNumber))"
    }
}

@available(iOS 27, macOS 27, *)
extension MetricReportValues {
    /// Reads the full-day entry: the interval entry with the longest duration.
    init(_ report: MetricReport) {
        self.init(periodStart: report.timeRange.start, periodEnd: report.timeRange.end)
        if let environment = report.environment {
            metadata = MetricKitReportMetadata(environment)
        }
        let entry = report.intervalEntries.max { $0.duration < $1.duration }
        for result in entry?.values ?? [] {
            read(result)
        }
    }

    private mutating func read(_ result: MetricResult) {
        switch result {
        case .timeToFirstDraw(let metric):
            timeToFirstDraw = Self.histogram(metric.histogram)
        case .optimizedTimeToFirstDraw(let metric):
            optimizedTimeToFirstDraw = Self.histogram(metric.histogram)
        case .applicationResumeTime(let metric):
            resumeTime = Self.histogram(metric.histogram)
        case .hangTime(let metric):
            hangTime = Self.histogram(metric.histogram)
        #if os(iOS)
        case .peakMemory(let metric):
            peakMemoryBytes = metric.value.converted(to: .bytes).value
        case .suspendedMemory(let metric):
            averageSuspendedMemoryBytes = metric.value.average.converted(to: .bytes).value
        #endif
        case .logicalDiskWrites(let metric):
            cumulativeDiskWritesBytes = metric.value.converted(to: .bytes).value
        case .cpuTime(let metric):
            cumulativeCPUTimeMilliseconds = metric.value.converted(to: .milliseconds).value
        case .foregroundTermination(let metric):
            foregroundMemoryLimitExits = metric.memoryLimitTerminationCount
        case .backgroundTermination(let metric):
            backgroundMemoryLimitExits = metric.memoryLimitTerminationCount
            backgroundMemoryPressureExits = metric.systemPressureTerminationCount
        default:
            break
        }
    }

    private static func histogram(_ histogram: Histogram<UnitDuration>) -> MetricKitHistogram {
        MetricKitHistogram(buckets: histogram.buckets.map { bucket in
            MetricKitHistogram.Bucket(
                start: bucket.lowerBound.converted(to: .milliseconds).value,
                end: bucket.upperBound.converted(to: .milliseconds).value,
                count: bucket.count
            )
        })
    }
}

@available(iOS 27, macOS 27, *)
extension DiagnosticReportValues {
    /// Returns `nil` for kinds the summary has no field for, such as memory exceptions.
    init?(_ report: DiagnosticReport) {
        let event: Event
        let tree: CallStackTree
        switch report.result {
        case .crash(let diagnostic):
            event = .crash(Crash(diagnostic))
            tree = diagnostic.callStackTree
        case .hang(let diagnostic):
            event = .hang(durationMilliseconds: diagnostic.hangDuration.converted(to: .milliseconds).value)
            tree = diagnostic.callStackTree
        case .cpuException(let diagnostic):
            event = .cpuException(
                totalCPUTimeMilliseconds: diagnostic.totalCPUTime.converted(to: .milliseconds).value,
                totalSampledTimeMilliseconds: diagnostic.totalSampledTime.converted(to: .milliseconds).value
            )
            tree = diagnostic.callStackTree
        case .diskWriteException(let diagnostic):
            event = .diskWriteException(writesCausedBytes: diagnostic.totalBytesWritten.converted(to: .bytes).value)
            tree = diagnostic.callStackTree
        case .appLaunch(let diagnostic):
            event = .appLaunch(launchDurationMilliseconds: diagnostic.launchDuration.converted(to: .milliseconds).value)
            tree = diagnostic.callStackTree
        default:
            return nil
        }
        self.init(
            periodStart: report.timeRange.start,
            periodEnd: report.timeRange.end,
            metadata: MetricKitReportMetadata(report.environment),
            binaries: Self.binaries(in: tree),
            event: event
        )
    }

    /// Binary names on the attributed thread, or on every thread if none is attributed.
    private static func binaries(in tree: CallStackTree) -> [String] {
        let threads = Array(tree.callStackThreads)
        let attributed = threads.filter { $0.threadAttributed == true }
        var names: Set<String> = []
        func collect(_ frames: ContiguousArray<CallStackFrame>) {
            for frame in frames {
                if let name = frame.binaryName(from: tree) {
                    names.insert(name)
                }
                collect(frame.subFrames)
            }
        }
        for thread in attributed.isEmpty ? threads : attributed {
            collect(thread.rootFrames)
        }
        return names.sorted()
    }
}

@available(iOS 27, macOS 27, *)
extension DiagnosticReportValues.Crash {
    init(_ diagnostic: CrashDiagnostic) {
        self.init(
            exceptionType: diagnostic.exceptionType,
            exceptionCode: diagnostic.exceptionCode.map { Int(truncatingIfNeeded: $0) },
            signal: diagnostic.signal,
            terminationReason: diagnostic.terminationReason?.description,
            virtualMemoryRegionInfo: diagnostic.virtualMemoryRegionInfo,
            objectiveCExceptionName: diagnostic.exceptionReason?.exceptionName,
            objectiveCExceptionMessage: diagnostic.exceptionReason?.composedMessage
        )
    }
}

#endif
