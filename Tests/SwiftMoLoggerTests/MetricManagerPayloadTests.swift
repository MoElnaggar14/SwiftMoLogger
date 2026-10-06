import Foundation
@testable import SwiftMoLogger
import SwiftMoLoggerTesting
import Testing

/// `MetricManagerPayloadSource` reads iOS 27 `MetricReport` / `DiagnosticReport`
/// values into `MetricReportValues` / `DiagnosticReportValues`, which write the
/// JSON shape of `jsonRepresentation()`. These tests check that the summaries
/// and the logged entries come out the same as for `MXMetricManager` payloads.
@Suite("MetricManager payloads")
struct MetricManagerPayloadTests {
    private let metadata = MetricKitReportMetadata(
        appVersion: "3.4.0",
        appBuildVersion: "412",
        osVersion: "iOS 27.0 (24A300)",
        deviceType: "iPhone18,1",
        platformArchitecture: "arm64e",
        bundleIdentifier: "com.example.shop"
    )

    /// 2026-10-04 00:00:00 +0000.
    private let periodStart = Date(timeIntervalSince1970: 1_791_072_000)

    private var metricValues: MetricReportValues {
        var values = MetricReportValues(periodStart: periodStart, periodEnd: periodStart + 86_340)
        values.metadata = metadata
        values.timeToFirstDraw = MetricKitHistogram(buckets: [
            .init(start: 0, end: 510, count: 60),
            .init(start: 510, end: 1_010, count: 40)
        ])
        values.optimizedTimeToFirstDraw = MetricKitHistogram(buckets: [.init(start: 0, end: 200, count: 12)])
        values.resumeTime = MetricKitHistogram(buckets: [.init(start: 20, end: 100, count: 5)])
        values.hangTime = MetricKitHistogram(buckets: [.init(start: 0, end: 100, count: 8)])
        values.peakMemoryBytes = 212_992_000
        values.averageSuspendedMemoryBytes = 48_128_000
        values.cumulativeDiskWritesBytes = 1_300_000
        values.cumulativeCPUTimeMilliseconds = 1_842_000
        values.foregroundMemoryLimitExits = 1
        values.backgroundMemoryLimitExits = 2
        values.backgroundMemoryPressureExits = 9
        return values
    }

    private func diagnostic(_ event: DiagnosticReportValues.Event) -> DiagnosticReportValues {
        DiagnosticReportValues(
            periodStart: periodStart,
            periodEnd: periodStart + 60,
            metadata: metadata,
            binaries: ["/System/Library/Frameworks/UIKitCore", "Shop", "ShopKit"],
            event: event
        )
    }

    // MARK: Metric reports

    @Test func metricReportParsesLikeAMetricPayload() throws {
        let payload = metricValues.payload
        #expect(payload.kind == .metrics)
        let summary = try #require(MetricPayloadSummary(jsonRepresentation: payload.json))

        #expect(summary.appVersion == "3.4.0")
        #expect(summary.appBuildVersion == "412")
        #expect(summary.osVersion == "iOS 27.0 (24A300)")
        #expect(summary.deviceType == "iPhone18,1")
        #expect(summary.periodStart == "2026-10-04 00:00:00 +0000")
        #expect(summary.periodEnd == "2026-10-04 23:59:00 +0000")
        #expect(summary.timeToFirstDraw == metricValues.timeToFirstDraw)
        #expect(summary.timeToFirstDraw?.percentileMilliseconds(0.95) == 1_010)
        #expect(summary.optimizedTimeToFirstDraw?.sampleCount == 12)
        #expect(summary.resumeTime?.averageMilliseconds == 60)
        #expect(summary.hangTime?.sampleCount == 8)
        #expect(summary.peakMemoryBytes == 212_992_000)
        #expect(summary.averageSuspendedMemoryBytes == 48_128_000)
        #expect(summary.cumulativeDiskWritesBytes == 1_300_000)
        #expect(summary.cumulativeCPUTimeMilliseconds == 1_842_000)
        #expect(summary.foregroundMemoryLimitExits == 1)
        #expect(summary.backgroundMemoryLimitExits == 2)
        #expect(summary.backgroundMemoryPressureExits == 9)
    }

    @Test func metricReportIsLoggedAsOneStructuredEntry() throws {
        let (logger, recorder) = MoLogger.recording()
        MetricKitPayloadLogger(logger: logger).log([metricValues.payload])

        let entries = recorder.entries(.info, tag: .performance)
        #expect(entries.count == 1)
        let metadata = try #require(entries.first?.metadata)
        #expect(metadata["app_version"] == .string("3.4.0"))
        #expect(metadata["period_start"] == .string("2026-10-04 00:00:00 +0000"))
        #expect(metadata["launch_ttfd_count"] == .int(100))
        #expect(metadata["launch_ttfd_p50_ms"] == .double(510))
        #expect(metadata["peak_memory_bytes"] == .int(212_992_000))
        #expect(metadata["cpu_time_ms"] == .double(1_842_000))
        #expect(metadata["memory_pressure_exits_background"] == .int(9))
    }

    @Test func emptyMetricReportLeavesFieldsEmpty() throws {
        let summary = try #require(MetricPayloadSummary(jsonRepresentation: MetricReportValues().payload.json))
        #expect(summary.appVersion == nil)
        #expect(summary.periodStart == nil)
        #expect(summary.timeToFirstDraw == nil)
        #expect(summary.peakMemoryBytes == nil)
        #expect(summary.foregroundMemoryLimitExits == nil)
    }

    // MARK: Diagnostic reports

    @Test func crashReportParsesLikeADiagnosticPayload() throws {
        let crash = DiagnosticReportValues.Crash(
            exceptionType: 1,
            exceptionCode: 0,
            signal: 11,
            terminationReason: "Namespace SIGNAL, Code 11",
            virtualMemoryRegionInfo: "0 is not in any region",
            objectiveCExceptionName: "NSInvalidArgumentException",
            objectiveCExceptionMessage: "unrecognized selector"
        )
        let payload = diagnostic(.crash(crash)).payload
        #expect(payload.kind == .diagnostics)
        let summary = try #require(DiagnosticPayloadSummary(jsonRepresentation: payload.json))

        #expect(summary.count == 1)
        #expect(summary.periodStart == "2026-10-04 00:00:00 +0000")
        let parsed = try #require(summary.crashes.first)
        #expect(parsed.exceptionName == "EXC_BAD_ACCESS")
        #expect(parsed.exceptionCode == 0)
        #expect(parsed.signalName == "SIGSEGV")
        #expect(parsed.terminationReason == "Namespace SIGNAL, Code 11")
        #expect(parsed.virtualMemoryRegionInfo == "0 is not in any region")
        #expect(parsed.objectiveCExceptionName == "NSInvalidArgumentException")
        #expect(parsed.objectiveCExceptionMessage == "unrecognized selector")
        #expect(parsed.context.appVersion == "3.4.0")
        #expect(parsed.context.appBuildVersion == "412")
        #expect(parsed.context.osVersion == "iOS 27.0 (24A300)")
        #expect(parsed.context.platformArchitecture == "arm64e")
        #expect(parsed.context.bundleIdentifier == "com.example.shop")
        #expect(parsed.context.binaries == ["Shop", "ShopKit"], "system binaries are left out")
    }

    @Test func crashWithoutObjectiveCExceptionHasNoReason() throws {
        let payload = diagnostic(.crash(DiagnosticReportValues.Crash(exceptionType: 10, signal: 6))).payload
        let summary = try #require(DiagnosticPayloadSummary(jsonRepresentation: payload.json))
        let parsed = try #require(summary.crashes.first)
        #expect(parsed.exceptionName == "EXC_CRASH")
        #expect(parsed.signalName == "SIGABRT")
        #expect(parsed.objectiveCExceptionName == nil)
        #expect(parsed.terminationReason == nil)
    }

    @Test func everyDiagnosticKindParses() throws {
        func summary(_ event: DiagnosticReportValues.Event) throws -> DiagnosticPayloadSummary {
            try #require(DiagnosticPayloadSummary(jsonRepresentation: diagnostic(event).payload.json))
        }
        #expect(try summary(.hang(durationMilliseconds: 2_500)).hangs.first?.durationMilliseconds == 2_500)

        let cpu = try summary(.cpuException(totalCPUTimeMilliseconds: 90_000, totalSampledTimeMilliseconds: 180_000))
        #expect(cpu.cpuExceptions.first?.totalCPUTimeMilliseconds == 90_000)
        #expect(cpu.cpuExceptions.first?.totalSampledTimeMilliseconds == 180_000)

        let disk = try summary(.diskWriteException(writesCausedBytes: 2_147_483_648))
        #expect(disk.diskWriteExceptions.first?.writesCausedBytes == 2_147_483_648)

        let launch = try summary(.appLaunch(launchDurationMilliseconds: 4_200))
        #expect(launch.appLaunches.first?.launchDurationMilliseconds == 4_200)
        #expect(launch.appLaunches.first?.context.binaries == ["Shop", "ShopKit"])
        #expect(launch.count == 1)
    }

    @Test func diagnosticReportIsLoggedLikeADiagnosticPayload() {
        let (logger, recorder) = MoLogger.recording()
        MetricKitPayloadLogger(logger: logger).log([
            diagnostic(.crash(DiagnosticReportValues.Crash(exceptionType: 1, signal: 11))).payload
        ])
        MetricKitPayloadLogger(logger: logger).log([diagnostic(.hang(durationMilliseconds: 2_500)).payload])

        let crash = recorder.entries(.critical, containing: "CRASH DETECTED", tag: .crash).first
        #expect(crash?.metadata["exception_name"] == .string("EXC_BAD_ACCESS"))
        #expect(crash?.metadata["binaries"] == .string("Shop, ShopKit"))
        let hang = recorder.entries(.warning, containing: "HANG", tag: .performance).first
        #expect(hang?.metadata["hang_duration_ms"] == .double(2_500))
        #expect(hang?.metadata["os_version"] == .string("iOS 27.0 (24A300)"))
    }

    // MARK: Source

    #if compiler(>=6.4) && canImport(MetricKit) && (os(iOS) || os(macOS))
    @Test func metricManagerSourceIsAPayloadSource() {
        if #available(iOS 27, macOS 27, *) {
            let sourceType: any MetricPayloadSource.Type = MetricManagerPayloadSource.self
            #expect(sourceType == MetricManagerPayloadSource.self)
        }
    }
    #endif
}
