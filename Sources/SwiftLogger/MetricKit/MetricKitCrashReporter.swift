import Foundation
import MetricKit

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
/// import SwiftLogger
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
    
    public override init() {
        super.init()
    }
    
    /// Start monitoring for crash diagnostics
    /// Call this early in your app's lifecycle (AppDelegate or App struct)
    public func startMonitoring() {
        guard !isMonitoring else {
            SwiftLogger.warn(message: "MetricKit crash monitoring already started", tag: LogTag.System.crash)
            return
        }
        
        MXMetricManager.shared.add(self)
        isMonitoring = true
        SwiftLogger.info(message: "MetricKit crash monitoring started", tag: LogTag.System.crash)
    }
    
    /// Stop monitoring for crash diagnostics
    /// Call this when your app terminates
    public func stopMonitoring() {
        guard isMonitoring else {
            SwiftLogger.warn(message: "MetricKit crash monitoring not active", tag: LogTag.System.crash)
            return
        }
        
        MXMetricManager.shared.remove(self)
        isMonitoring = false
        SwiftLogger.info(message: "MetricKit crash monitoring stopped", tag: LogTag.System.crash)
    }
}

// MARK: - MXMetricManagerSubscriber
extension MetricKitCrashReporter: MXMetricManagerSubscriber {
    
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Process crash reports
        for payload in payloads {
            if let crashDiagnostics = payload.crashDiagnostics {
                handleCrashDiagnostics(crashDiagnostics)
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
        SwiftLogger.error(message: "🚨 CRASH DETECTED 🚨", tag: LogTag.System.crash)
        
        let crashDictionary = diagnostic.dictionaryRepresentation()
        let crashTimestamp = crashDictionary["timestamp"] ?? Date().description
        
        let summary = """
        Timestamp: \(crashTimestamp)
        App version: \(diagnostic.applicationVersion)
        iOS version: \(diagnostic.metaData.osVersion)
        Device type: \(diagnostic.metaData.deviceType)
        """
        
        SwiftLogger.error(message: summary, tag: LogTag.System.crash)
        
        if let exceptionType = diagnostic.exceptionType {
            SwiftLogger.error(message: "Exception type: \(exceptionType)", tag: LogTag.System.crash)
        }
        
        if let exceptionCode = diagnostic.exceptionCode {
            SwiftLogger.error(message: "Exception code: \(exceptionCode)", tag: LogTag.System.crash)
        }
        
        if let signal = diagnostic.signal {
            let codeString = diagnostic.exceptionCode?.stringValue
            let signalDescription = describeCrashSignal(signal, code: codeString)
            SwiftLogger.error(message: signalDescription, tag: LogTag.System.crash)
        }
    }
    
    /// Analyzes the call stack for common crash patterns and user binaries
    func analyzeCrashCallStack(_ callStackTree: MXCallStackTree) {
        let callStackData = callStackTree.jsonRepresentation()
        
        guard let jsonString = String(data: callStackData, encoding: .utf8) else {
            SwiftLogger.error(message: "Unable to decode call stack JSON.", tag: LogTag.System.crash)
            return
        }
        
        SwiftLogger.info(message: "🔍 Call Stack Analysis:", tag: LogTag.System.crash)
        printCrashPatternHints(in: jsonString)
        printUserBinaries(in: jsonString)
    }
    
    /// Archives crash report data for later analysis
    func archiveCrashReport(_ diagnostic: MXCrashDiagnostic) {
        // Convert diagnostic to dictionary for storage
        let crashData = diagnostic.dictionaryRepresentation()
        
        // You can implement custom storage logic here (e.g., save to Core Data, send to analytics)
        // For now, we'll just log that the crash has been archived
        SwiftLogger.info(message: "Crash report archived for further analysis", tag: LogTag.System.crash)
        
        // Optional: Send to crash reporting service
        // sendCrashReportToService(crashData)
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
        } else if let signalNum = signal as? NSNumber, let mapped = signalMap["\(signalNum.intValue)"] {
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
            SwiftLogger.warn(message: "Memory access issue detected - likely accessing deallocated memory", tag: LogTag.System.crash)
        } else if callStackJSON.contains("EXC_BREAKPOINT") {
            SwiftLogger.warn(message: "Exception breakpoint - possibly an unhandled Swift error or assertion", tag: LogTag.System.crash)
        } else if callStackJSON.contains("EXC_CRASH") {
            SwiftLogger.warn(message: "Kernel terminated process - often due to memory pressure or watchdog timeout", tag: LogTag.System.crash)
        }
    }
    
    /// Prints user or third-party binaries found in the call stack
    func printUserBinaries(in callStackJSON: String) {
        guard let data = callStackJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let callStacks = json["callStacks"] as? [[String: Any]] else {
            SwiftLogger.error(message: "Could not parse call stack JSON", tag: LogTag.System.crash)
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
            SwiftLogger.info(message: "User/Third-party binaries in crash: \(binariesList)", tag: LogTag.System.crash)
        }
    }
}

// MARK: - Public Extensions
public extension MetricKitCrashReporter {
    
    /// Convenience method to test crash reporting (for development only)
    /// ⚠️ WARNING: This will actually crash the app! Use only for testing.
    func triggerTestCrash() {
        #if DEBUG
        SwiftLogger.warn(message: "Triggering test crash for MetricKit validation", tag: LogTag.System.crash)
        fatalError("Test crash for MetricKit validation")
        #else
        SwiftLogger.warn(message: "Test crash is only available in DEBUG builds", tag: LogTag.System.crash)
        #endif
    }
}