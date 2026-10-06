import Foundation

// The iOS 27 `MetricManager` API delivers typed, `Codable` reports instead of
// `MXMetricPayload` / `MXDiagnosticPayload`, and they have no
// `jsonRepresentation()`. `MetricManagerPayloadSource` reads the values it
// needs into these plain types, which write them out in the JSON shape of
// `jsonRepresentation()`. The summaries and `MetricKitPayloadLogger` then
// parse them unchanged, so the logged entries are the same for both sources.
//
// These types don't depend on MetricKit, so the mapping is tested on every toolchain.

/// Device and app fields MetricKit attaches to every report.
struct MetricKitReportMetadata: Sendable, Equatable {
    var appVersion: String?
    var appBuildVersion: String?
    var osVersion: String?
    var deviceType: String?
    var platformArchitecture: String?
    var bundleIdentifier: String?

    /// The fields as `metaData` / `diagnosticMetaData` holds them.
    var jsonObject: [String: Any] {
        var object: [String: Any] = [:]
        object["appVersion"] = appVersion
        object["appBuildVersion"] = appBuildVersion
        object["osVersion"] = osVersion
        object["deviceType"] = deviceType
        object["platformArchitecture"] = platformArchitecture
        object["bundleIdentifier"] = bundleIdentifier
        return object
    }
}

/// The values of a daily metric report that ``MetricPayloadSummary`` reads.
/// Durations are in milliseconds and sizes in bytes.
struct MetricReportValues: Sendable, Equatable {
    var periodStart: Date?
    var periodEnd: Date?
    var metadata = MetricKitReportMetadata()

    var timeToFirstDraw: MetricKitHistogram?
    var optimizedTimeToFirstDraw: MetricKitHistogram?
    var resumeTime: MetricKitHistogram?
    var hangTime: MetricKitHistogram?

    var peakMemoryBytes: Double?
    var averageSuspendedMemoryBytes: Double?
    var cumulativeDiskWritesBytes: Double?
    var cumulativeCPUTimeMilliseconds: Double?

    var foregroundMemoryLimitExits: Int?
    var backgroundMemoryLimitExits: Int?
    var backgroundMemoryPressureExits: Int?

    var payload: MetricKitPayload {
        MetricKitPayload(kind: .metrics, json: MetricKitReportJSON.data(jsonObject))
    }

    /// The report in the shape of `MXMetricPayload.jsonRepresentation()`.
    var jsonObject: [String: Any] {
        typealias JSON = MetricKitReportJSON
        var object: [String: Any] = ["metaData": metadata.jsonObject]
        object["latestApplicationVersion"] = metadata.appVersion
        object["timeStampBegin"] = periodStart.map(JSON.timestamp)
        object["timeStampEnd"] = periodEnd.map(JSON.timestamp)

        var launch: [String: Any] = [:]
        launch["histogrammedTimeToFirstDraw"] = timeToFirstDraw.map(JSON.histogram)
        launch["histogrammedOptimizedTimeToFirstDraw"] = optimizedTimeToFirstDraw.map(JSON.histogram)
        launch["histogrammedApplicationResumeTime"] = resumeTime.map(JSON.histogram)
        JSON.set(launch, "applicationLaunchMetrics", in: &object)

        var responsiveness: [String: Any] = [:]
        responsiveness["histogrammedApplicationHangTime"] = hangTime.map(JSON.histogram)
        JSON.set(responsiveness, "applicationResponsivenessMetrics", in: &object)

        var memory: [String: Any] = [:]
        memory["peakMemoryUsage"] = peakMemoryBytes
        memory["averageSuspendedMemory"] = averageSuspendedMemoryBytes.map { ["averageValue": $0] }
        JSON.set(memory, "memoryMetrics", in: &object)

        var diskIO: [String: Any] = [:]
        diskIO["cumulativeLogicalWrites"] = cumulativeDiskWritesBytes
        JSON.set(diskIO, "diskIOMetrics", in: &object)

        var cpu: [String: Any] = [:]
        cpu["cumulativeCPUTime"] = cumulativeCPUTimeMilliseconds
        JSON.set(cpu, "cpuMetrics", in: &object)

        var foreground: [String: Any] = [:]
        foreground["cumulativeMemoryResourceLimitExitCount"] = foregroundMemoryLimitExits
        var background: [String: Any] = [:]
        background["cumulativeMemoryResourceLimitExitCount"] = backgroundMemoryLimitExits
        background["cumulativeMemoryPressureExitCount"] = backgroundMemoryPressureExits
        var exits: [String: Any] = [:]
        JSON.set(foreground, "foregroundExitData", in: &exits)
        JSON.set(background, "backgroundExitData", in: &exits)
        JSON.set(exits, "applicationExitMetrics", in: &object)
        return object
    }
}

/// The values of one diagnostic report that ``DiagnosticPayloadSummary`` reads.
/// Durations are in milliseconds and sizes in bytes.
struct DiagnosticReportValues: Sendable, Equatable {
    struct Crash: Sendable, Equatable {
        var exceptionType: Int?
        var exceptionCode: Int?
        var signal: Int?
        var terminationReason: String?
        var virtualMemoryRegionInfo: String?
        var objectiveCExceptionName: String?
        var objectiveCExceptionMessage: String?
    }

    enum Event: Sendable, Equatable {
        case crash(Crash)
        case hang(durationMilliseconds: Double)
        case cpuException(totalCPUTimeMilliseconds: Double, totalSampledTimeMilliseconds: Double)
        case diskWriteException(writesCausedBytes: Double)
        case appLaunch(launchDurationMilliseconds: Double)
    }

    var periodStart: Date?
    var periodEnd: Date?
    var metadata = MetricKitReportMetadata()
    /// Binaries on the attributed thread's call stack (every thread if none is attributed).
    var binaries: [String] = []
    var event: Event

    var payload: MetricKitPayload {
        MetricKitPayload(kind: .diagnostics, json: MetricKitReportJSON.data(jsonObject))
    }

    /// The report in the shape of `MXDiagnosticPayload.jsonRepresentation()`,
    /// holding a single diagnostic.
    var jsonObject: [String: Any] {
        typealias JSON = MetricKitReportJSON
        var metaData = metadata.jsonObject
        var diagnostic: [String: Any] = [:]
        let key: String
        switch event {
        case .crash(let crash):
            key = "crashDiagnostics"
            metaData["exceptionType"] = crash.exceptionType
            metaData["exceptionCode"] = crash.exceptionCode
            metaData["signal"] = crash.signal
            metaData["terminationReason"] = crash.terminationReason
            metaData["virtualMemoryRegionInfo"] = crash.virtualMemoryRegionInfo
            var reason: [String: Any] = [:]
            reason["exceptionName"] = crash.objectiveCExceptionName
            reason["composedMessage"] = crash.objectiveCExceptionMessage
            if !reason.isEmpty {
                metaData["exceptionReason"] = reason
            }
        case .hang(let duration):
            key = "hangDiagnostics"
            diagnostic["hangDuration"] = duration
        case let .cpuException(cpuTime, sampledTime):
            key = "cpuExceptionDiagnostics"
            diagnostic["totalCPUTime"] = cpuTime
            diagnostic["totalSampledTime"] = sampledTime
        case .diskWriteException(let bytes):
            key = "diskWriteExceptionDiagnostics"
            diagnostic["writesCaused"] = bytes
        case .appLaunch(let duration):
            key = "appLaunchDiagnostics"
            diagnostic["launchDuration"] = duration
        }
        diagnostic["diagnosticMetaData"] = metaData
        diagnostic["callStackTree"] = JSON.callStackTree(binaries: binaries)

        var object: [String: Any] = [key: [diagnostic]]
        object["timeStampBegin"] = periodStart.map(JSON.timestamp)
        object["timeStampEnd"] = periodEnd.map(JSON.timestamp)
        return object
    }
}

/// Writes values in the JSON shape of `jsonRepresentation()`.
enum MetricKitReportJSON {
    static func data(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    /// `2026-10-04 00:00:00 +0000`, as MetricKit writes `timeStampBegin` and `timeStampEnd`.
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter.string(from: date)
    }

    /// Buckets in milliseconds, as `{"histogramNumBuckets": …, "histogramValue": [{"bucketStart": …}]}`.
    static func histogram(_ histogram: MetricKitHistogram) -> [String: Any] {
        [
            "histogramNumBuckets": histogram.buckets.count,
            "histogramValue": histogram.buckets.map { bucket -> [String: Any] in
                ["bucketStart": bucket.start, "bucketEnd": bucket.end, "bucketCount": bucket.count]
            }
        ]
    }

    /// One attributed thread with a root frame per binary, which is all the summary reads.
    static func callStackTree(binaries: [String]) -> [String: Any] {
        let frames = binaries.map { ["binaryName": $0] }
        return ["callStacks": [["threadAttributed": true, "callStackRootFrames": frames]]]
    }

    /// Adds `section` under `key` unless it's empty, as MetricKit leaves out sections it has no data for.
    static func set(_ section: [String: Any], _ key: String, in object: inout [String: Any]) {
        if !section.isEmpty {
            object[key] = section
        }
    }
}
