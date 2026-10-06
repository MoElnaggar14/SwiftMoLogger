import Foundation

/// The parts of a MetricKit diagnostic payload (`MXDiagnosticPayload`) worth logging.
///
/// Built from the payload's `jsonRepresentation()`, so a recorded payload can
/// be replayed in tests. Durations are in milliseconds and sizes in bytes.
/// App-launch diagnostics are delivered from iOS 16 and macOS 13; the other
/// kinds from iOS 14 and macOS 12.
public struct DiagnosticPayloadSummary: Sendable, Equatable, Codable {
    /// Fields every diagnostic carries in its `diagnosticMetaData`.
    public struct Context: Sendable, Equatable, Codable {
        public let appVersion: String?
        public let appBuildVersion: String?
        public let osVersion: String?
        public let deviceType: String?
        public let platformArchitecture: String?
        public let bundleIdentifier: String?
        /// Binaries on the call stack of the thread the diagnostic is attributed to
        /// (every thread if none is), excluding `/System/` and `/usr/lib/` paths.
        public let binaries: [String]
    }

    public struct Crash: Sendable, Equatable, Codable {
        public let context: Context
        /// The Mach exception type, such as 1 for `EXC_BAD_ACCESS`.
        public let exceptionType: Int?
        public let exceptionCode: Int?
        /// The POSIX signal, such as 11 for `SIGSEGV`.
        public let signal: Int?
        public let terminationReason: String?
        public let virtualMemoryRegionInfo: String?
        /// The name of an uncaught Objective-C exception (iOS 17 and later).
        public let objectiveCExceptionName: String?
        /// The message of an uncaught Objective-C exception (iOS 17 and later).
        public let objectiveCExceptionMessage: String?

        /// `EXC_BAD_ACCESS`, `EXC_CRASH`, … for the exception type.
        public var exceptionName: String? {
            exceptionType.flatMap { DiagnosticPayloadSummary.machExceptionNames[$0] }
        }

        /// `SIGSEGV`, `SIGABRT`, … for the signal.
        public var signalName: String? {
            signal.flatMap { DiagnosticPayloadSummary.signalNames[$0] }
        }
    }

    public struct Hang: Sendable, Equatable, Codable {
        public let context: Context
        public let durationMilliseconds: Double?
    }

    public struct CPUException: Sendable, Equatable, Codable {
        public let context: Context
        public let totalCPUTimeMilliseconds: Double?
        public let totalSampledTimeMilliseconds: Double?
    }

    public struct DiskWriteException: Sendable, Equatable, Codable {
        public let context: Context
        public let writesCausedBytes: Double?
    }

    public struct AppLaunch: Sendable, Equatable, Codable {
        public let context: Context
        public let launchDurationMilliseconds: Double?
    }

    /// Start of the period the payload covers, as MetricKit wrote it.
    public let periodStart: String?
    /// End of the period the payload covers, as MetricKit wrote it.
    public let periodEnd: String?
    public let crashes: [Crash]
    public let hangs: [Hang]
    public let cpuExceptions: [CPUException]
    public let diskWriteExceptions: [DiskWriteException]
    public let appLaunches: [AppLaunch]

    /// Parses `MXDiagnosticPayload.jsonRepresentation()`. Returns `nil` if the data isn't a JSON object.
    public init?(jsonRepresentation data: Data) {
        guard let object = MetricKitJSON.object(from: data) else { return nil }
        self.init(object: object)
    }

    init(object: [String: Any]) {
        typealias JSON = MetricKitJSON
        func diagnostics(_ key: String) -> [Diagnostic] {
            (object[key] as? [[String: Any]] ?? []).map(Diagnostic.init)
        }
        periodStart = JSON.string(object["timeStampBegin"])
        periodEnd = JSON.string(object["timeStampEnd"])
        crashes = diagnostics("crashDiagnostics").map { item -> Crash in
            let reason = item["exceptionReason"] as? [String: Any]
            return Crash(
                context: item.context,
                exceptionType: JSON.int(item["exceptionType"]),
                exceptionCode: JSON.int(item["exceptionCode"]),
                signal: JSON.int(item["signal"]),
                terminationReason: JSON.string(item["terminationReason"]),
                virtualMemoryRegionInfo: JSON.string(item["virtualMemoryRegionInfo"]),
                objectiveCExceptionName: JSON.string(JSON.first(reason, ["exceptionName", "exceptionType"])),
                objectiveCExceptionMessage: JSON.string(reason?["composedMessage"])
            )
        }
        hangs = diagnostics("hangDiagnostics").map { item in
            Hang(context: item.context, durationMilliseconds: JSON.milliseconds(item["hangDuration"]))
        }
        cpuExceptions = diagnostics("cpuExceptionDiagnostics").map { item in
            CPUException(
                context: item.context,
                totalCPUTimeMilliseconds: JSON.milliseconds(item["totalCPUTime"]),
                totalSampledTimeMilliseconds: JSON.milliseconds(item["totalSampledTime"])
            )
        }
        diskWriteExceptions = diagnostics("diskWriteExceptionDiagnostics").map { item in
            DiskWriteException(context: item.context, writesCausedBytes: JSON.bytes(item["writesCaused"]))
        }
        appLaunches = diagnostics("appLaunchDiagnostics").map { item in
            AppLaunch(context: item.context, launchDurationMilliseconds: JSON.milliseconds(item["launchDuration"]))
        }
    }

    /// The number of diagnostics of every kind.
    public var count: Int {
        crashes.count + hangs.count + cpuExceptions.count + diskWriteExceptions.count + appLaunches.count
    }
}

// MARK: - Parsing

private extension DiagnosticPayloadSummary {
    /// One entry of a `…Diagnostics` array.
    struct Diagnostic {
        let item: [String: Any]
        let metaData: [String: Any]

        init(_ item: [String: Any]) {
            self.item = item
            self.metaData = item["diagnosticMetaData"] as? [String: Any] ?? [:]
        }

        /// A `diagnosticMetaData` field, or the same key on the diagnostic itself.
        subscript(key: String) -> Any? {
            metaData[key] ?? item[key]
        }

        var context: Context {
            Context(
                appVersion: MetricKitJSON.string(self["appVersion"]),
                appBuildVersion: MetricKitJSON.string(self["appBuildVersion"]),
                osVersion: MetricKitJSON.string(self["osVersion"]),
                deviceType: MetricKitJSON.string(self["deviceType"]),
                platformArchitecture: MetricKitJSON.string(self["platformArchitecture"]),
                bundleIdentifier: MetricKitJSON.string(self["bundleIdentifier"]),
                binaries: binaries
            )
        }

        var binaries: [String] {
            let callStacks = MetricKitJSON.value(item, "callStackTree", "callStacks") as? [[String: Any]] ?? []
            let attributed = callStacks.filter { ($0["threadAttributed"] as? Bool) == true }
            var names: Set<String> = []
            for callStack in attributed.isEmpty ? callStacks : attributed {
                collectBinaries(in: callStack["callStackRootFrames"] as? [[String: Any]] ?? [], into: &names)
            }
            return names.sorted()
        }

        private func collectBinaries(in frames: [[String: Any]], into names: inout Set<String>) {
            for frame in frames {
                if let name = frame["binaryName"] as? String,
                   !name.hasPrefix("/System/"),
                   !name.hasPrefix("/usr/lib/") {
                    names.insert(name)
                }
                collectBinaries(in: frame["subFrames"] as? [[String: Any]] ?? [], into: &names)
            }
        }
    }

    static let machExceptionNames: [Int: String] = [
        1: "EXC_BAD_ACCESS", 2: "EXC_BAD_INSTRUCTION", 3: "EXC_ARITHMETIC", 4: "EXC_EMULATION",
        5: "EXC_SOFTWARE", 6: "EXC_BREAKPOINT", 7: "EXC_SYSCALL", 8: "EXC_MACH_SYSCALL",
        9: "EXC_RPC_ALERT", 10: "EXC_CRASH", 11: "EXC_RESOURCE", 12: "EXC_GUARD", 13: "EXC_CORPSE_NOTIFY"
    ]

    static let signalNames: [Int: String] = [
        4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT", 8: "SIGFPE", 9: "SIGKILL",
        10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE", 15: "SIGTERM"
    ]
}
