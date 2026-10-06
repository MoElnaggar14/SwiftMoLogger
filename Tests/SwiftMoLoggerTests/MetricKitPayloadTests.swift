import Foundation
import SwiftMoLogger
import SwiftMoLoggerTesting
import Testing

/// MetricKit payloads are parsed from their JSON, so these tests replay
/// recorded payloads from `Fixtures/MetricKit` instead of building `MX` objects.
@Suite("MetricKit payloads")
struct MetricKitPayloadTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/MetricKit")
        )
        return try Data(contentsOf: url)
    }

    // MARK: Metric payloads

    @Test func metricPayloadParsesLaunchHangMemoryDiskAndCPU() throws {
        let summary = try #require(MetricPayloadSummary(jsonRepresentation: try fixture("metric-payload")))

        #expect(summary.appVersion == "3.4.0")
        #expect(summary.appBuildVersion == "412")
        #expect(summary.osVersion == "iPhone OS 18.6 (22G86)")
        #expect(summary.deviceType == "iPhone16,1")
        #expect(summary.periodStart == "2026-10-04 00:00:00 +0000")
        #expect(summary.periodEnd == "2026-10-04 23:59:00 +0000")

        let firstDraw = try #require(summary.timeToFirstDraw)
        #expect(firstDraw.buckets.count == 3)
        #expect(firstDraw.sampleCount == 100)
        #expect(firstDraw.averageMilliseconds == 475)
        #expect(firstDraw.percentileMilliseconds(0.5) == 510)
        #expect(firstDraw.percentileMilliseconds(0.95) == 1_010)
        #expect(summary.optimizedTimeToFirstDraw?.sampleCount == 12)
        #expect(summary.resumeTime?.averageMilliseconds == 60)
        #expect(summary.hangTime?.percentileMilliseconds(0.95) == 400)

        #expect(summary.peakMemoryBytes == 212_992_000)
        #expect(summary.averageSuspendedMemoryBytes == 48_128_000)
        #expect(summary.cumulativeDiskWritesBytes == 1_300_000)
        #expect(summary.cumulativeCPUTimeMilliseconds == 1_842_000)
        #expect(summary.foregroundMemoryLimitExits == 1)
        #expect(summary.backgroundMemoryLimitExits == 2)
        #expect(summary.backgroundMemoryPressureExits == 9)
    }

    @Test func metricPayloadIsLoggedAsOneStructuredEntry() throws {
        let (logger, recorder) = MoLogger.recording()
        MetricKitPayloadLogger(logger: logger).log(
            MetricKitPayload(kind: .metrics, json: try fixture("metric-payload"))
        )

        let entries = recorder.entries(.info, tag: .performance)
        #expect(entries.count == 1)
        let metadata = try #require(entries.first?.metadata)
        #expect(metadata["app_version"] == .string("3.4.0"))
        #expect(metadata["period_start"] == .string("2026-10-04 00:00:00 +0000"))
        #expect(metadata["launch_ttfd_count"] == .int(100))
        #expect(metadata["launch_ttfd_avg_ms"] == .double(475))
        #expect(metadata["launch_ttfd_p50_ms"] == .double(510))
        #expect(metadata["launch_ttfd_p95_ms"] == .double(1_010))
        #expect(metadata["launch_ttfd_optimized_count"] == .int(12))
        #expect(metadata["resume_p50_ms"] == .double(60))
        #expect(metadata["hang_time_count"] == .int(10))
        #expect(metadata["hang_time_avg_ms"] == .double(90))
        #expect(metadata["peak_memory_bytes"] == .int(212_992_000))
        #expect(metadata["disk_writes_bytes"] == .int(1_300_000))
        #expect(metadata["cpu_time_ms"] == .double(1_842_000))
        #expect(metadata["memory_limit_exits_foreground"] == .int(1))
        #expect(metadata["memory_pressure_exits_background"] == .int(9))
    }

    @Test func missingSectionsLeaveFieldsEmpty() throws {
        let json = Data(#"{"appVersion": "1.0", "metaData": {"osVersion": "iPhone OS 17.0"}}"#.utf8)
        let summary = try #require(MetricPayloadSummary(jsonRepresentation: json))
        #expect(summary.appVersion == "1.0")
        #expect(summary.timeToFirstDraw == nil)
        #expect(summary.peakMemoryBytes == nil)
        #expect(summary.foregroundMemoryLimitExits == nil)

        let (logger, recorder) = MoLogger.recording()
        MetricKitPayloadLogger(logger: logger).log(summary)
        let metadata = try #require(recorder.recorded().first?.metadata)
        #expect(!metadata.keys.contains("launch_ttfd_count"))
        #expect(!metadata.keys.contains("peak_memory_bytes"))
        #expect(metadata["os_version"] == .string("iPhone OS 17.0"))
    }

    @Test func measurementsParseInEitherNumberFormat() throws {
        let json = Data(#"""
        {
          "memoryMetrics": {"peakMemoryUsage": "1,5 MB"},
          "diskIOMetrics": {"cumulativeLogicalWrites": "1.300,5 kB"},
          "cpuMetrics": {"cumulativeCPUTime": "2 min"},
          "applicationLaunchMetrics": {
            "histogrammedTimeToFirstDraw": {
              "histogramNumBuckets": 1,
              "histogramValue": [{"bucketCount": 4, "bucketStart": "1 sec", "bucketEnd": "1.5 sec"}]
            }
          }
        }
        """#.utf8)
        let summary = try #require(MetricPayloadSummary(jsonRepresentation: json))
        #expect(summary.peakMemoryBytes == 1_500_000)
        #expect(summary.cumulativeDiskWritesBytes == 1_300_500)
        #expect(summary.cumulativeCPUTimeMilliseconds == 120_000)
        #expect(summary.timeToFirstDraw?.buckets == [MetricKitHistogram.Bucket(start: 1_000, end: 1_500, count: 4)])
    }

    @Test func emptyHistogramHasNoEstimates() {
        let histogram = MetricKitHistogram(buckets: [.init(start: 0, end: 10, count: 0)])
        #expect(histogram.sampleCount == 0)
        #expect(histogram.averageMilliseconds == nil)
        #expect(histogram.percentileMilliseconds(0.5) == nil)
    }

    // MARK: Diagnostic payloads

    @Test func diagnosticPayloadParsesEveryKind() throws {
        let summary = try #require(DiagnosticPayloadSummary(jsonRepresentation: try fixture("diagnostic-payload")))
        #expect(summary.count == 6)

        let crash = try #require(summary.crashes.first)
        #expect(crash.exceptionType == 1)
        #expect(crash.exceptionName == "EXC_BAD_ACCESS")
        #expect(crash.signal == 11)
        #expect(crash.signalName == "SIGSEGV")
        #expect(crash.terminationReason == "Namespace SIGNAL, Code 11 Segmentation fault: 11")
        #expect(crash.context.appVersion == "3.4.0")
        #expect(crash.context.bundleIdentifier == "com.example.shop")
        #expect(crash.context.binaries == ["Shop", "ShopKit", "libswiftCore.dylib"],
                "subframes are walked, and only the attributed thread counts")

        let exception = summary.crashes[1]
        #expect(exception.exceptionName == "EXC_CRASH")
        #expect(exception.signalName == "SIGABRT")
        #expect(exception.objectiveCExceptionName == "NSRangeException")
        #expect(exception.objectiveCExceptionMessage?.contains("beyond bounds") == true)

        #expect(summary.hangs.first?.durationMilliseconds == 4_500)
        #expect(summary.cpuExceptions.first?.totalCPUTimeMilliseconds == 92_000)
        #expect(summary.cpuExceptions.first?.totalSampledTimeMilliseconds == 180_000)
        #expect(summary.diskWriteExceptions.first?.writesCausedBytes == 1_073_741_824)
        #expect(summary.appLaunches.first?.launchDurationMilliseconds == 6_200)
    }

    @Test func diagnosticsAreLoggedOneEntryEach() throws {
        let (logger, recorder) = MoLogger.recording()
        MetricKitPayloadLogger(logger: logger).log([
            MetricKitPayload(kind: .diagnostics, json: try fixture("diagnostic-payload"))
        ])

        #expect(recorder.contains(.info, containing: "Received 1 diagnostic payload(s)", tag: .crash))

        let crashes = recorder.entries(.critical, containing: "CRASH DETECTED", tag: .crash)
        #expect(crashes.count == 2)
        let crash = try #require(crashes.first?.metadata)
        #expect(crash["exception_name"] == .string("EXC_BAD_ACCESS"))
        #expect(crash["signal_name"] == .string("SIGSEGV"))
        #expect(crash["app_version"] == .string("3.4.0"))
        #expect(crash["binaries"] == .string("Shop, ShopKit, libswiftCore.dylib"))
        #expect(crash["hint"] == .string("Memory access issue — likely deallocated memory"))
        #expect(crashes.last?.metadata["objc_exception"] == .string("NSRangeException"))

        let hang = try #require(recorder.entries(.warning, containing: "HANG", tag: .performance).first)
        #expect(hang.metadata["hang_duration_ms"] == .double(4_500))
        let cpu = try #require(recorder.entries(.warning, containing: "CPU exception").first)
        #expect(cpu.metadata["cpu_time_ms"] == .double(92_000))
        let disk = try #require(recorder.entries(.warning, containing: "Disk-write exception").first)
        #expect(disk.metadata["disk_writes_bytes"] == .int(1_073_741_824))
        let launch = try #require(recorder.entries(.warning, containing: "Slow app launch").first)
        #expect(launch.metadata["launch_duration_ms"] == .double(6_200))
    }

    @Test func undecodablePayloadIsLoggedAsAnError() {
        let (logger, recorder) = MoLogger.recording()
        MetricKitPayloadLogger(logger: logger).log(MetricKitPayload(kind: .metrics, json: Data("not json".utf8)))
        #expect(recorder.contains(.error, containing: "Unable to decode MetricKit metrics payload"))
    }

    // MARK: Source port

    #if canImport(MetricKit) && (os(iOS) || os(macOS))
    @Test func reporterLogsWhatItsSourceDelivers() throws {
        let (logger, recorder) = MoLogger.recording()
        let source = ReplaySource()
        let reporter = MetricKitCrashReporter(logger: logger, source: source)

        source.replay([MetricKitPayload(kind: .metrics, json: try fixture("metric-payload"))])
        #expect(!recorder.contains(tag: .performance), "nothing is delivered before monitoring starts")

        reporter.startMonitoring()
        source.replay([
            MetricKitPayload(kind: .metrics, json: try fixture("metric-payload")),
            MetricKitPayload(kind: .diagnostics, json: try fixture("diagnostic-payload"))
        ])
        #expect(recorder.count(.info, containing: "MetricKit metrics") == 1)
        #expect(recorder.count(.critical, containing: "CRASH DETECTED") == 2)

        reporter.stopMonitoring()
        #expect(source.stopCount == 1)
        #expect(source.handler == nil)
    }
    #endif
}

/// Replays recorded payloads, standing in for `MXMetricManager`.
private final class ReplaySource: MetricPayloadSource {
    private(set) var handler: (@Sendable ([MetricKitPayload]) -> Void)?
    private(set) var stopCount = 0

    func start(delivering handler: @escaping @Sendable ([MetricKitPayload]) -> Void) {
        self.handler = handler
    }

    func stop() {
        handler = nil
        stopCount += 1
    }

    func replay(_ payloads: [MetricKitPayload]) {
        handler?(payloads)
    }
}
