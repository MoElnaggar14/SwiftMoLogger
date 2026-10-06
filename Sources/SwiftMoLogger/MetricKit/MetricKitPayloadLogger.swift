import Foundation

/// Logs MetricKit payloads as structured entries.
///
/// ``MetricKitCrashReporter`` uses it for every payload its source delivers.
/// Use it directly to log payloads you recorded or received some other way:
///
/// ```swift
/// let payloadLogger = MetricKitPayloadLogger(logger: environment.logger)
/// payloadLogger.log(MetricKitPayload(kind: .metrics, json: payload.jsonRepresentation()))
/// ```
///
/// Each metric payload becomes one `.info` entry tagged `.performance`. Each
/// crash becomes a `.critical` entry tagged `.crash`; hangs, CPU and disk-write
/// exceptions and slow launches become `.warning` entries tagged `.performance`.
/// Durations are logged in milliseconds (`_ms` keys) and sizes in bytes (`_bytes` keys).
public struct MetricKitPayloadLogger: Sendable {
    private let logger: MoLogger

    public init(logger: MoLogger) {
        self.logger = logger
    }

    /// Parses and logs a batch of payloads, as a source delivers them.
    public func log(_ payloads: [MetricKitPayload]) {
        let diagnosticCount = payloads.filter { $0.kind == .diagnostics }.count
        if diagnosticCount > 0 {
            logger.info(
                "Received \(diagnosticCount) diagnostic payload(s)",
                tag: .crash,
                metadata: ["payload_count": .int(Int64(diagnosticCount))]
            )
        }
        for payload in payloads {
            log(payload)
        }
    }

    /// Parses and logs one payload. A payload that isn't valid JSON is logged as an error.
    public func log(_ payload: MetricKitPayload) {
        switch payload.kind {
        case .metrics:
            if let summary = MetricPayloadSummary(jsonRepresentation: payload.json) {
                log(summary)
                return
            }
        case .diagnostics:
            if let summary = DiagnosticPayloadSummary(jsonRepresentation: payload.json) {
                log(summary)
                return
            }
        }
        logger.error(
            "Unable to decode MetricKit \(payload.kind.rawValue) payload",
            tag: payload.kind == .metrics ? .performance : .crash,
            metadata: ["payload_bytes": .int(Int64(payload.json.count))]
        )
    }

    /// Logs a metric payload as one `.info` entry.
    public func log(_ summary: MetricPayloadSummary) {
        logger.info("MetricKit metrics", tag: .performance, metadata: Self.metadata(for: summary))
    }

    /// Logs one entry per diagnostic in the payload.
    public func log(_ summary: DiagnosticPayloadSummary) {
        for crash in summary.crashes {
            logger.critical("🚨 CRASH DETECTED", tag: .crash, metadata: Self.metadata(for: crash))
        }
        for hang in summary.hangs {
            var metadata = Self.metadata(for: hang.context)
            metadata["hang_duration_ms"] = Self.value(hang.durationMilliseconds)
            logger.warning("🐌 HANG detected", tag: .performance, metadata: metadata)
        }
        for exception in summary.cpuExceptions {
            var metadata = Self.metadata(for: exception.context)
            metadata["cpu_time_ms"] = Self.value(exception.totalCPUTimeMilliseconds)
            metadata["sampled_time_ms"] = Self.value(exception.totalSampledTimeMilliseconds)
            logger.warning("CPU exception", tag: .performance, metadata: metadata)
        }
        for exception in summary.diskWriteExceptions {
            var metadata = Self.metadata(for: exception.context)
            metadata["disk_writes_bytes"] = Self.integer(exception.writesCausedBytes)
            logger.warning("Disk-write exception", tag: .performance, metadata: metadata)
        }
        for launch in summary.appLaunches {
            var metadata = Self.metadata(for: launch.context)
            metadata["launch_duration_ms"] = Self.value(launch.launchDurationMilliseconds)
            logger.warning("Slow app launch", tag: .performance, metadata: metadata)
        }
    }
}

// MARK: - Metadata

private extension MetricKitPayloadLogger {
    static func metadata(for summary: MetricPayloadSummary) -> LogMetadata {
        var metadata = LogMetadata()
        metadata["app_version"] = value(summary.appVersion)
        metadata["app_build"] = value(summary.appBuildVersion)
        metadata["os_version"] = value(summary.osVersion)
        metadata["device_type"] = value(summary.deviceType)
        metadata["period_start"] = value(summary.periodStart)
        metadata["period_end"] = value(summary.periodEnd)
        add(summary.timeToFirstDraw, as: "launch_ttfd", to: &metadata)
        add(summary.optimizedTimeToFirstDraw, as: "launch_ttfd_optimized", to: &metadata)
        add(summary.resumeTime, as: "resume", to: &metadata)
        add(summary.hangTime, as: "hang_time", to: &metadata)
        metadata["peak_memory_bytes"] = integer(summary.peakMemoryBytes)
        metadata["avg_suspended_memory_bytes"] = integer(summary.averageSuspendedMemoryBytes)
        metadata["disk_writes_bytes"] = integer(summary.cumulativeDiskWritesBytes)
        metadata["cpu_time_ms"] = value(summary.cumulativeCPUTimeMilliseconds)
        metadata["memory_limit_exits_foreground"] = value(summary.foregroundMemoryLimitExits)
        metadata["memory_limit_exits_background"] = value(summary.backgroundMemoryLimitExits)
        metadata["memory_pressure_exits_background"] = value(summary.backgroundMemoryPressureExits)
        return metadata
    }

    /// `<prefix>_count`, `<prefix>_avg_ms`, `<prefix>_p50_ms` and `<prefix>_p95_ms`.
    static func add(_ histogram: MetricKitHistogram?, as prefix: String, to metadata: inout LogMetadata) {
        guard let histogram, histogram.sampleCount > 0 else { return }
        metadata["\(prefix)_count"] = .int(Int64(histogram.sampleCount))
        metadata["\(prefix)_avg_ms"] = value(histogram.averageMilliseconds)
        metadata["\(prefix)_p50_ms"] = value(histogram.percentileMilliseconds(0.5))
        metadata["\(prefix)_p95_ms"] = value(histogram.percentileMilliseconds(0.95))
    }

    static func metadata(for crash: DiagnosticPayloadSummary.Crash) -> LogMetadata {
        var metadata = Self.metadata(for: crash.context)
        metadata["exception_type"] = value(crash.exceptionType)
        metadata["exception_name"] = value(crash.exceptionName)
        metadata["exception_code"] = value(crash.exceptionCode)
        metadata["signal"] = value(crash.signal)
        metadata["signal_name"] = value(crash.signalName)
        metadata["termination_reason"] = value(crash.terminationReason)
        metadata["objc_exception"] = value(crash.objectiveCExceptionName)
        metadata["objc_exception_message"] = value(crash.objectiveCExceptionMessage)
        metadata["hint"] = value(hint(for: crash))
        return metadata
    }

    static func metadata(for context: DiagnosticPayloadSummary.Context) -> LogMetadata {
        var metadata = LogMetadata()
        metadata["app_version"] = value(context.appVersion)
        metadata["app_build"] = value(context.appBuildVersion)
        metadata["os_version"] = value(context.osVersion)
        metadata["device_type"] = value(context.deviceType)
        if !context.binaries.isEmpty {
            metadata["binaries"] = .string(context.binaries.joined(separator: ", "))
        }
        return metadata
    }

    static func hint(for crash: DiagnosticPayloadSummary.Crash) -> String? {
        if crash.objectiveCExceptionName != nil {
            return "Uncaught Objective-C exception"
        }
        switch crash.exceptionType {
        case 1?: return "Memory access issue — likely deallocated memory"
        case 2?: return "Illegal instruction — often a Swift runtime trap"
        case 6?: return "Assertion failure or unhandled Swift error"
        case 10?: return "Process terminated — abort, memory pressure or timeout"
        case 11?: return "Resource limit exceeded — memory, CPU or wakeups"
        default: return nil
        }
    }

    static func value(_ string: String?) -> LogMetadataValue? {
        string.map { .string($0) }
    }

    static func value(_ double: Double?) -> LogMetadataValue? {
        double.map { .double($0) }
    }

    static func value(_ int: Int?) -> LogMetadataValue? {
        int.map { .int(Int64($0)) }
    }

    /// Rounds to a whole number, for byte counts.
    static func integer(_ double: Double?) -> LogMetadataValue? {
        double.flatMap { Int64(exactly: $0.rounded()) }.map { .int($0) }
    }
}
