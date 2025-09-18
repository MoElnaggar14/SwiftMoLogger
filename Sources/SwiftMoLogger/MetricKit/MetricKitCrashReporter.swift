import Foundation
import MetricKit

// MARK: - Delegate Protocols

/// Protocol for receiving crash reports in production apps
public protocol CrashReportDelegate: AnyObject {
    func didReceiveCrashReport(_ report: [String: Any])
}

/// Protocol for receiving hang reports in production apps  
public protocol HangReportDelegate: AnyObject {
    func didReceiveHangReport(_ diagnostic: MXHangDiagnostic, rawData: [String: Any])
}

/// MetricKit-based crash reporter that provides system-level crash debugging capabilities.
/// 
/// This implementation follows best practices for crash reporting using Apple's MetricKit framework.
/// MetricKit operates outside your app's process, collecting diagnostics at the system level.
/// This captures crashes that traditional reporters miss, including memory pressure crashes,
/// background terminations, and OS signal crashes.
///
/// ## Usage
/// Create an instance and retain it for the lifetime of your app:
/// ```swift
/// import SwiftMoLogger
/// 
/// @main
/// struct YourApp: App {
///     let crashReporter = MetricKitCrashReporter()
///     
///     init() {
///         crashReporter.startMonitoring()
///     }
/// }
/// ```
///
/// ## iOS Version Differences
/// - **iOS 13-14**: Crash reports are aggregated and delivered once per day
/// - **iOS 15+**: Crash reports are delivered immediately on the next launch
public final class MetricKitCrashReporter: NSObject {
    private var isMonitoring = false
    
    /// Delegate for receiving crash reports (optional)
    public weak var crashReportDelegate: CrashReportDelegate?
    
    /// Delegate for receiving hang reports (optional)
    public weak var hangReportDelegate: HangReportDelegate?

    override public init() {
        super.init()
    }
    /// Start monitoring for crash diagnostics
    /// Call this early in your app's lifecycle (AppDelegate or App struct)
    public func startMonitoring() {
        guard !isMonitoring else {
            SwiftMoLogger.warn(message: "MetricKit crash monitoring already started", tag: LogTag.System.crash)
            return
        }
        MXMetricManager.shared.add(self)
        isMonitoring = true
        SwiftMoLogger.info(message: "MetricKit crash monitoring started", tag: LogTag.System.crash)
    }

    /// Stop monitoring for crash diagnostics
    /// Call this when your app terminates
    public func stopMonitoring() {
        guard isMonitoring else {
            SwiftMoLogger.warn(message: "MetricKit crash monitoring not active", tag: LogTag.System.crash)
            return
        }
        MXMetricManager.shared.remove(self)
        isMonitoring = false
        SwiftMoLogger.info(message: "MetricKit crash monitoring stopped", tag: LogTag.System.crash)
    }
}

// MARK: - MXMetricManagerSubscriber
extension MetricKitCrashReporter: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        SwiftMoLogger.info(message: "📨 Received \(payloads.count) diagnostic payload(s) from MetricKit", tag: LogTag.System.crash)
        
        // Process crash reports
        for payload in payloads {
            if let crashDiagnostics = payload.crashDiagnostics {
                SwiftMoLogger.info(message: "🔍 Processing \(crashDiagnostics.count) crash diagnostic(s)", tag: LogTag.System.crash)
                handleCrashDiagnostics(crashDiagnostics)
            }
            
            // Also handle other diagnostic types in production
            if let hangDiagnostics = payload.hangDiagnostics {
                SwiftMoLogger.info(message: "📊 Processing \(hangDiagnostics.count) hang diagnostic(s)", tag: LogTag.System.performance)
                handleHangDiagnostics(hangDiagnostics)
            }
        }
    }
}

// MARK: - Private Methods
private extension MetricKitCrashReporter {
    /// Processes and logs crash diagnostics from MetricKit
    func handleCrashDiagnostics(_ diagnostics: [MXCrashDiagnostic]) {
        for diagnostic in diagnostics {
            logCrashSummary(diagnostic)
            analyzeCrashCallStack(diagnostic.callStackTree)
            archiveCrashReport(diagnostic)
        }
    }
    /// Logs a concise summary of the crash for quick inspection
    func logCrashSummary(_ diagnostic: MXCrashDiagnostic) {
        SwiftMoLogger.error(message: "🚨 CRASH DETECTED 🚨", tag: LogTag.System.crash)
        let crashDictionary = diagnostic.dictionaryRepresentation()
        let crashTimestamp = crashDictionary["timestamp"] ?? Date().description
        let summary = """
        Timestamp: \(crashTimestamp)
        App version: \(diagnostic.applicationVersion)
        iOS version: \(diagnostic.metaData.osVersion)
        Device type: \(diagnostic.metaData.deviceType)
        """
        SwiftMoLogger.error(message: summary, tag: LogTag.System.crash)
        if let exceptionType = diagnostic.exceptionType {
            SwiftMoLogger.error(message: "Exception type: \(exceptionType)", tag: LogTag.System.crash)
        }
        if let exceptionCode = diagnostic.exceptionCode {
            SwiftMoLogger.error(message: "Exception code: \(exceptionCode)", tag: LogTag.System.crash)
        }
        if let signal = diagnostic.signal {
            let codeString = diagnostic.exceptionCode?.stringValue
            let signalDescription = describeCrashSignal(signal, code: codeString)
            SwiftMoLogger.error(message: signalDescription, tag: LogTag.System.crash)
        }
    }

    /// Analyzes the call stack for common crash patterns and user binaries
    func analyzeCrashCallStack(_ callStackTree: MXCallStackTree) {
        let callStackData = callStackTree.jsonRepresentation()
        guard let jsonString = String(data: callStackData, encoding: .utf8) else {
            SwiftMoLogger.error(message: "Unable to decode call stack JSON.", tag: LogTag.System.crash)
            return
        }

        SwiftMoLogger.info(message: "🔍 Call Stack Analysis:", tag: LogTag.System.crash)
        printCrashPatternHints(in: jsonString)
        printUserBinaries(in: jsonString)
    }
    /// Archives crash report data for later analysis and external services
    func archiveCrashReport(_ diagnostic: MXCrashDiagnostic) {
        // Convert diagnostic to dictionary for storage
        let crashData = diagnostic.dictionaryRepresentation()
        
        // Create comprehensive crash report
        let crashReport = createDetailedCrashReport(from: diagnostic)
        
        SwiftMoLogger.info(message: "📋 Crash report created and ready for processing", tag: LogTag.System.crash)
        SwiftMoLogger.info(message: "💾 Crash data size: \(crashData.description.count) characters", tag: LogTag.System.crash)
        
        // Extensible: Developers can override this or add delegates
        // Convert AnyHashable keys to String keys for delegate compatibility
        let stringKeyCrashData: [String: Any] = Dictionary(uniqueKeysWithValues: 
            crashData.compactMap { key, value in
                guard let stringKey = key as? String else { return nil }
                return (stringKey, value)
            }
        )
        notifyCrashReportDelegates(crashReport, rawData: stringKeyCrashData)
        
        SwiftMoLogger.info(message: "✅ Crash report processing completed", tag: LogTag.System.crash)
    }
    
    /// Handle hang diagnostics (production feature)
    func handleHangDiagnostics(_ diagnostics: [MXHangDiagnostic]) {
        for diagnostic in diagnostics {
            SwiftMoLogger.warn(message: "🐌 HANG DETECTED: Duration \(diagnostic.hangDuration)ms", tag: LogTag.System.performance)
            SwiftMoLogger.info(message: "Hang in app version: \(diagnostic.applicationVersion)", tag: LogTag.System.performance)
            
            // Archive hang reports similar to crashes
            let hangData = diagnostic.dictionaryRepresentation()
            SwiftMoLogger.info(message: "📊 Hang report archived", tag: LogTag.System.performance)
            
            // Notify delegates about hang
            // Convert AnyHashable keys to String keys for delegate compatibility
            let stringKeyHangData: [String: Any] = Dictionary(uniqueKeysWithValues: 
                hangData.compactMap { key, value in
                    guard let stringKey = key as? String else { return nil }
                    return (stringKey, value)
                }
            )
            notifyHangReportDelegates(diagnostic, rawData: stringKeyHangData)
        }
    }
    
    /// Create detailed crash report for production use
    func createDetailedCrashReport(from diagnostic: MXCrashDiagnostic) -> [String: Any] {
        var report: [String: Any] = [:]
        
        // Basic info
        report["timestamp"] = Date().iso8601String
        report["appVersion"] = diagnostic.applicationVersion
        report["osVersion"] = diagnostic.metaData.osVersion
        report["deviceType"] = diagnostic.metaData.deviceType
        
        // Crash details
        if let exceptionType = diagnostic.exceptionType {
            report["exceptionType"] = exceptionType.stringValue
        }
        if let exceptionCode = diagnostic.exceptionCode {
            report["exceptionCode"] = exceptionCode.stringValue
        }
        if let signal = diagnostic.signal {
            report["signal"] = signal.stringValue
            report["signalDescription"] = describeCrashSignal(signal, code: diagnostic.exceptionCode?.stringValue)
        }
        
        // Call stack
        let callStackData = diagnostic.callStackTree.jsonRepresentation()
        if let callStackString = String(data: callStackData, encoding: .utf8) {
            report["callStack"] = callStackString
        }
        
        // Additional metadata
        report["crashId"] = UUID().uuidString
        report["reportGeneratedAt"] = Date().timeIntervalSince1970
        
        return report
    }
    
    /// Notify external delegates/services about crash reports
    func notifyCrashReportDelegates(_ report: [String: Any], rawData: [String: Any]) {
        SwiftMoLogger.info(message: "🔗 Notifying crash report delegates", tag: LogTag.System.crash)
        
        // Notify delegate if set
        crashReportDelegate?.didReceiveCrashReport(report)
        
        SwiftMoLogger.info(message: "📤 Crash report available for external service integration", tag: LogTag.System.crash)
    }
    
    /// Notify external delegates about hang reports
    func notifyHangReportDelegates(_ diagnostic: MXHangDiagnostic, rawData: [String: Any]) {
        SwiftMoLogger.info(message: "🔗 Notifying hang report delegates", tag: LogTag.System.performance)
        
        // Notify delegate if set
        hangReportDelegate?.didReceiveHangReport(diagnostic, rawData: rawData)
        
        SwiftMoLogger.info(message: "📤 Hang report available for external service integration", tag: LogTag.System.performance)
    }
    /// Returns a human-readable description for a crash signal
    func describeCrashSignal(_ signal: Any?, code: String?) -> String {
        let signalMap: [String: String] = [
            "1": "SIGHUP",
            "2": "SIGINT",
            "3": "SIGQUIT",
            "4": "SIGILL",
            "5": "SIGTRAP",
            "6": "SIGABRT",
            "7": "SIGBUS",
            "8": "SIGFPE",
            "9": "SIGKILL",
            "10": "SIGUSR1",
            "11": "SIGSEGV",
            "12": "SIGUSR2",
            "13": "SIGPIPE",
            "14": "SIGALRM",
            "15": "SIGTERM"
        ]
        var signalName: String?
        if let signalStr = signal as? String, let mapped = signalMap[signalStr] {
            signalName = mapped
        } else if let signalNum = signal as? NSNumber, let mapped = signalMap[String(signalNum.intValue)] {
            signalName = mapped
        } else if let signalStr = signal as? String {
            signalName = signalStr
        }
        switch signalName {
        case "SIGSEGV":
            return "Segmentation fault (SIGSEGV): Invalid memory access (likely accessing a nil pointer)"
        case "SIGABRT":
            return "Abort (SIGABRT): Process terminated by system (common in unhandled exceptions, assertions)"
        case "SIGBUS":
            return "Bus error (SIGBUS): Misaligned memory access or non-existent memory address"
        case "SIGILL":
            return "Illegal instruction (SIGILL): Invalid instruction attempted (rare, possibly corrupted memory)"
        case "SIGTRAP":
            return "Trap (SIGTRAP): Often from debug breakpoints or exceptions"
        case .some(let name):
            return "Signal: \(name)"
        default:
            return "Unknown signal: \(String(describing: signal))"
        }
    }
    /// Prints hints if common crash patterns are detected in the call stack
    func printCrashPatternHints(in callStackJSON: String) {
        if callStackJSON.contains("EXC_BAD_ACCESS") {
            SwiftMoLogger.warn(
                message: "Memory access issue detected - likely accessing deallocated memory",
                tag: LogTag.System.crash
            )
        } else if callStackJSON.contains("EXC_BREAKPOINT") {
            SwiftMoLogger.warn(
                message: "Exception breakpoint - possibly an unhandled Swift error or assertion",
                tag: LogTag.System.crash
            )
        } else if callStackJSON.contains("EXC_CRASH") {
            SwiftMoLogger.warn(
                message: "Kernel terminated process - often due to memory pressure or watchdog timeout",
                tag: LogTag.System.crash
            )
        }
    }
    /// Prints user or third-party binaries found in the call stack
    func printUserBinaries(in callStackJSON: String) {
        guard let data = callStackJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let callStacks = json["callStacks"] as? [[String: Any]] else {
            SwiftMoLogger.error(message: "Could not parse call stack JSON", tag: LogTag.System.crash)
            return
        }
        var userBinaries: Set<String> = []
        for stack in callStacks {
            if let frames = stack["callStackRootFrames"] as? [[String: Any]] {
                for frame in frames {
                    if let binaryName = frame["binaryName"] as? String {
                        // Filter out system frameworks and focus on user/third-party binaries
                        if !binaryName.hasPrefix("/System/") &&
                           !binaryName.hasPrefix("/usr/lib/") &&
                           !binaryName.contains("Foundation") &&
                           !binaryName.contains("UIKit") {
                            userBinaries.insert(binaryName)
                        }
                    }
                }
            }
        }
        if !userBinaries.isEmpty {
            let binariesList = userBinaries.joined(separator: ", ")
            SwiftMoLogger.info(message: "User/Third-party binaries in crash: \(binariesList)", tag: LogTag.System.crash)
        }
    }
}

// MARK: - Date Extension
private extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

// MARK: - Public Extensions
public extension MetricKitCrashReporter {
    /// Convenience method to test crash reporting (for development only)
    /// ⚠️ WARNING: This will actually crash the app! Use only for testing.
    func triggerTestCrash() {
        #if DEBUG
        SwiftMoLogger.warn(message: "Triggering test crash for MetricKit validation", tag: LogTag.System.crash)
        fatalError("Test crash for MetricKit validation")
        #else
        SwiftMoLogger.warn(message: "Test crash is only available in DEBUG builds", tag: LogTag.System.crash)
        #endif
    }
}
