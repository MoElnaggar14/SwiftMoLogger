import Foundation

#if canImport(MetricKit) && (os(iOS) || os(macOS))
import MetricKit

/// Protocol for receiving crash reports
public protocol CrashReportDelegate: AnyObject, Sendable {
    func didReceiveCrashReport(_ report: [String: Any])
}

/// Protocol for receiving hang reports
public protocol HangReportDelegate: AnyObject, Sendable {
    func didReceiveHangReport(_ diagnostic: MXHangDiagnostic, rawData: [String: Any])
}

/// MetricKit-based crash reporter for system-level crash debugging.
///
/// MetricKit collects crashes, hangs, CPU exceptions, and disk-write events
/// outside the app's own process — catching cases that in-process reporters
/// miss (jetsam, watchdog timeouts, app-launch crashes). Diagnostic payloads
/// arrive on the next launch.
///
/// Usage:
/// ```swift
/// let reporter = MetricKitCrashReporter()
/// reporter.startMonitoring()
/// ```
public final class MetricKitCrashReporter: NSObject {
    private var isMonitoring = false

    public weak var crashReportDelegate: CrashReportDelegate?
    public weak var hangReportDelegate: HangReportDelegate?

    public override init() {
        super.init()
    }

    public func startMonitoring() {
        guard !isMonitoring else {
            SwiftMoLogger.warn("MetricKit monitoring already active", tag: .crash)
            return
        }
        MXMetricManager.shared.add(self)
        isMonitoring = true
        SwiftMoLogger.info("MetricKit monitoring started", tag: .crash)
    }

    public func stopMonitoring() {
        guard isMonitoring else {
            SwiftMoLogger.warn("MetricKit monitoring not active", tag: .crash)
            return
        }
        MXMetricManager.shared.remove(self)
        isMonitoring = false
        SwiftMoLogger.info("MetricKit monitoring stopped", tag: .crash)
    }

    /// Force a fatal crash for end-to-end MetricKit pipeline validation.
    /// Now public (was internal in v2 despite being documented as public).
    public func triggerTestCrash() {
        #if DEBUG
        SwiftMoLogger.warn("Triggering test crash for validation", tag: .crash)
        fatalError("Test crash for MetricKit validation")
        #else
        SwiftMoLogger.warn("Test crashes only available in DEBUG builds", tag: .crash)
        #endif
    }
}

extension MetricKitCrashReporter: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        SwiftMoLogger.info(
            "Received \(payloads.count) diagnostic payload(s)",
            tag: .crash,
            metadata: ["payload_count": .int(Int64(payloads.count))]
        )

        for payload in payloads {
            if let crashDiagnostics = payload.crashDiagnostics {
                handleCrashDiagnostics(crashDiagnostics)
            }
            if let hangDiagnostics = payload.hangDiagnostics {
                handleHangDiagnostics(hangDiagnostics)
            }
        }
    }
}

private extension MetricKitCrashReporter {
    func handleCrashDiagnostics(_ diagnostics: [MXCrashDiagnostic]) {
        for diagnostic in diagnostics {
            logCrashSummary(diagnostic)
            analyzeCrashCallStack(diagnostic.callStackTree)
            archiveCrashReport(diagnostic)
        }
    }

    func logCrashSummary(_ diagnostic: MXCrashDiagnostic) {
        var metadata: LogMetadata = [
            "app_version": .string(diagnostic.applicationVersion),
            "os_version": .string(diagnostic.metaData.osVersion),
            "device_type": .string(diagnostic.metaData.deviceType)
        ]
        if let exceptionType = diagnostic.exceptionType {
            metadata["exception_type"] = .int(Int64(truncating: exceptionType))
        }
        if let signal = diagnostic.signal {
            metadata["signal"] = .int(Int64(truncating: signal))
        }
        SwiftMoLogger.critical("🚨 CRASH DETECTED", tag: .crash, metadata: metadata)
    }

    func analyzeCrashCallStack(_ callStackTree: MXCallStackTree) {
        let callStackData = callStackTree.jsonRepresentation()
        guard let jsonString = String(data: callStackData, encoding: .utf8) else {
            SwiftMoLogger.error("Unable to decode call stack", tag: .crash)
            return
        }
        printCrashPatternHints(in: jsonString)
        printUserBinaries(in: jsonString)
    }

    func archiveCrashReport(_ diagnostic: MXCrashDiagnostic) {
        let crashReport = createDetailedCrashReport(from: diagnostic)
        let crashData = diagnostic.dictionaryRepresentation()
        let stringKeyCrashData: [String: Any] = Dictionary(uniqueKeysWithValues:
            crashData.compactMap { key, value in
                guard let stringKey = key as? String else { return nil }
                return (stringKey, value)
            }
        )
        crashReportDelegate?.didReceiveCrashReport(crashReport)
        _ = stringKeyCrashData
    }

    func handleHangDiagnostics(_ diagnostics: [MXHangDiagnostic]) {
        for diagnostic in diagnostics {
            SwiftMoLogger.warn(
                "🐌 HANG detected",
                tag: .performance,
                metadata: ["hang_duration_ms": .double(diagnostic.hangDuration.converted(to: .milliseconds).value)]
            )
            let hangData = diagnostic.dictionaryRepresentation()
            let stringKeyHangData: [String: Any] = Dictionary(uniqueKeysWithValues:
                hangData.compactMap { key, value in
                    guard let stringKey = key as? String else { return nil }
                    return (stringKey, value)
                }
            )
            hangReportDelegate?.didReceiveHangReport(diagnostic, rawData: stringKeyHangData)
        }
    }

    func createDetailedCrashReport(from diagnostic: MXCrashDiagnostic) -> [String: Any] {
        var report: [String: Any] = [:]
        report["timestamp"] = ISO8601DateFormatter().string(from: Date())
        report["appVersion"] = diagnostic.applicationVersion
        report["osVersion"] = diagnostic.metaData.osVersion
        report["deviceType"] = diagnostic.metaData.deviceType
        if let exceptionType = diagnostic.exceptionType {
            report["exceptionType"] = exceptionType.intValue
        }
        if let signal = diagnostic.signal {
            report["signal"] = signal.intValue
        }
        if let exceptionCode = diagnostic.exceptionCode {
            report["exceptionCode"] = exceptionCode.intValue
        }
        let callStackData = diagnostic.callStackTree.jsonRepresentation()
        if let callStackString = String(data: callStackData, encoding: .utf8) {
            report["callStack"] = callStackString
        }
        return report
    }

    func printCrashPatternHints(in callStackJSON: String) {
        if callStackJSON.contains("EXC_BAD_ACCESS") {
            SwiftMoLogger.warn("Memory access issue — likely deallocated memory", tag: .crash)
        } else if callStackJSON.contains("EXC_BREAKPOINT") {
            SwiftMoLogger.warn("Assertion failure or unhandled Swift error", tag: .crash)
        } else if callStackJSON.contains("EXC_CRASH") {
            SwiftMoLogger.warn("Process terminated — memory pressure or timeout", tag: .crash)
        }
    }

    func printUserBinaries(in callStackJSON: String) {
        guard let data = callStackJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let callStacks = json["callStacks"] as? [[String: Any]] else {
            return
        }
        var userBinaries: Set<String> = []
        for callStack in callStacks {
            if let frames = callStack["callStackRootFrames"] as? [[String: Any]] {
                for frame in frames {
                    if let binaryName = frame["binaryName"] as? String,
                       !binaryName.hasPrefix("/System/"),
                       !binaryName.hasPrefix("/usr/lib/") {
                        userBinaries.insert(binaryName)
                    }
                }
            }
        }
        if !userBinaries.isEmpty {
            SwiftMoLogger.info(
                "User binaries in crash",
                tag: .crash,
                metadata: ["binaries": .string(userBinaries.sorted().joined(separator: ", "))]
            )
        }
    }
}

#endif
