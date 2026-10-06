import Foundation

/// A MetricKit histogram of durations, such as time to first draw or hang time.
///
/// MetricKit reports these as buckets with a count each, not as individual
/// samples, so the average and percentiles are estimates: the average uses
/// each bucket's midpoint and a percentile is the upper bound of the bucket
/// it falls in.
public struct MetricKitHistogram: Sendable, Equatable, Codable {
    public struct Bucket: Sendable, Equatable, Codable {
        /// Lower bound in milliseconds.
        public let start: Double
        /// Upper bound in milliseconds.
        public let end: Double
        public let count: Int

        public init(start: Double, end: Double, count: Int) {
            self.start = start
            self.end = end
            self.count = count
        }
    }

    /// Buckets in ascending order.
    public let buckets: [Bucket]

    public init(buckets: [Bucket]) {
        self.buckets = buckets.sorted { $0.start < $1.start }
    }

    /// Reads `{"histogramNumBuckets": …, "histogramValue": {"0": {"bucketStart": …}}}`.
    init?(json value: Any?) {
        guard let object = value as? [String: Any] else { return nil }
        let rawBuckets: [[String: Any]]
        if let array = object["histogramValue"] as? [[String: Any]] {
            rawBuckets = array
        } else if let keyed = object["histogramValue"] as? [String: Any] {
            rawBuckets = keyed
                .sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }
                .compactMap { $0.value as? [String: Any] }
        } else {
            return nil
        }
        let buckets = rawBuckets.compactMap { bucket -> Bucket? in
            guard let start = MetricKitJSON.milliseconds(bucket["bucketStart"]),
                  let end = MetricKitJSON.milliseconds(bucket["bucketEnd"]) else {
                return nil
            }
            return Bucket(start: start, end: end, count: MetricKitJSON.int(bucket["bucketCount"]) ?? 0)
        }
        guard !buckets.isEmpty else { return nil }
        self.init(buckets: buckets)
    }

    /// The number of samples across all buckets.
    public var sampleCount: Int {
        buckets.reduce(0) { $0 + $1.count }
    }

    /// The estimated mean in milliseconds, or `nil` with no samples.
    public var averageMilliseconds: Double? {
        let total = sampleCount
        guard total > 0 else { return nil }
        let weighted = buckets.reduce(0.0) { $0 + ($1.start + $1.end) / 2 * Double($1.count) }
        return weighted / Double(total)
    }

    /// The estimated percentile in milliseconds (`0.5` is the median), or `nil` with no samples.
    public func percentileMilliseconds(_ fraction: Double) -> Double? {
        let total = sampleCount
        guard total > 0 else { return nil }
        let target = Double(total) * min(max(fraction, 0), 1)
        var cumulative = 0
        for bucket in buckets where bucket.count >= 1 {
            cumulative += bucket.count
            if Double(cumulative) >= target { return bucket.end }
        }
        return buckets.last?.end
    }
}

/// The parts of a MetricKit metric payload (`MXMetricPayload`) worth logging.
///
/// Built from the payload's `jsonRepresentation()`, so a recorded payload can
/// be replayed in tests. Durations are in milliseconds and sizes in bytes.
/// Every field is optional: MetricKit leaves out sections it has no data for.
public struct MetricPayloadSummary: Sendable, Equatable, Codable {
    public let appVersion: String?
    public let appBuildVersion: String?
    public let osVersion: String?
    public let deviceType: String?
    /// Start of the period the payload covers, as MetricKit wrote it.
    public let periodStart: String?
    /// End of the period the payload covers, as MetricKit wrote it.
    public let periodEnd: String?

    /// Time from launch to the first frame.
    public let timeToFirstDraw: MetricKitHistogram?
    /// Time to first draw for launches the system prewarmed (iOS 15.2 and later).
    public let optimizedTimeToFirstDraw: MetricKitHistogram?
    /// Time to resume from the background.
    public let resumeTime: MetricKitHistogram?
    /// Main-thread hangs.
    public let hangTime: MetricKitHistogram?

    public let peakMemoryBytes: Double?
    public let averageSuspendedMemoryBytes: Double?
    public let cumulativeDiskWritesBytes: Double?
    public let cumulativeCPUTimeMilliseconds: Double?

    /// Foreground terminations for exceeding the memory limit.
    public let foregroundMemoryLimitExits: Int?
    /// Background terminations for exceeding the memory limit.
    public let backgroundMemoryLimitExits: Int?
    /// Background terminations to free memory for other apps (jetsam).
    public let backgroundMemoryPressureExits: Int?

    /// Parses `MXMetricPayload.jsonRepresentation()`. Returns `nil` if the data isn't a JSON object.
    public init?(jsonRepresentation data: Data) {
        guard let object = MetricKitJSON.object(from: data) else { return nil }
        self.init(object: object)
    }

    init(object: [String: Any]) {
        typealias JSON = MetricKitJSON
        let metaData = object["metaData"] as? [String: Any]
        appVersion = JSON.string(JSON.first(object, ["appVersion", "latestApplicationVersion"]))
        appBuildVersion = JSON.string(metaData?["appBuildVersion"])
        osVersion = JSON.string(metaData?["osVersion"])
        deviceType = JSON.string(metaData?["deviceType"])
        periodStart = JSON.string(object["timeStampBegin"])
        periodEnd = JSON.string(object["timeStampEnd"])

        let launch = object["applicationLaunchMetrics"] as? [String: Any]
        timeToFirstDraw = MetricKitHistogram(json: JSON.first(launch, [
            "histogrammedTimeToFirstDrawKey", "histogrammedTimeToFirstDraw"
        ]))
        optimizedTimeToFirstDraw = MetricKitHistogram(json: JSON.first(launch, [
            "histogrammedOptimizedTimeToFirstDrawKey", "histogrammedOptimizedTimeToFirstDraw"
        ]))
        resumeTime = MetricKitHistogram(json: JSON.first(launch, [
            "histogrammedResumeTime", "histogrammedApplicationResumeTimeKey", "histogrammedApplicationResumeTime"
        ]))
        let responsiveness = object["applicationResponsivenessMetrics"] as? [String: Any]
        hangTime = MetricKitHistogram(json: JSON.first(responsiveness, [
            "histogrammedAppHangTime", "histogrammedApplicationHangTime"
        ]))

        peakMemoryBytes = JSON.bytes(JSON.value(object, "memoryMetrics", "peakMemoryUsage"))
        averageSuspendedMemoryBytes = JSON.bytes(
            JSON.value(object, "memoryMetrics", "averageSuspendedMemory", "averageValue")
        )
        cumulativeDiskWritesBytes = JSON.bytes(JSON.value(object, "diskIOMetrics", "cumulativeLogicalWrites"))
        cumulativeCPUTimeMilliseconds = JSON.milliseconds(JSON.value(object, "cpuMetrics", "cumulativeCPUTime"))

        let exits = object["applicationExitMetrics"] as? [String: Any]
        foregroundMemoryLimitExits = JSON.int(
            JSON.value(exits, "foregroundExitData", "cumulativeMemoryResourceLimitExitCount")
        )
        backgroundMemoryLimitExits = JSON.int(
            JSON.value(exits, "backgroundExitData", "cumulativeMemoryResourceLimitExitCount")
        )
        backgroundMemoryPressureExits = JSON.int(
            JSON.value(exits, "backgroundExitData", "cumulativeMemoryPressureExitCount")
        )
    }
}
