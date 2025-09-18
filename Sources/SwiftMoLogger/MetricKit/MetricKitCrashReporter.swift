import Foundation
import MetricKit

// MARK: - Delegate Protocols

/// Protocol for receiving crash reports
public protocol CrashReportDelegate: AnyObject {
    func didReceiveCrashReport(_ report: [String: Any])
}

/// Protocol for receiving hang reports  
public protocol HangReportDelegate: AnyObject {
    func didReceiveHangReport(_ diagnostic: MXHangDiagnostic, rawData: [String: Any])
}

// MARK: - MetricKit Crash Reporter

/// MetricKit-based crash reporter for system-level crash debugging
///
/// ## Usage
/// ```swift
/// let crashReporter = MetricKitCrashReporter()
/// crashReporter.startMonitoring()
/// ```
///
/// ## Features
/// - System-level crash collection
/// - Background termination detection
/// - Memory pressure crashes
/// - iOS 15+ immediate delivery
public final class MetricKitCrashReporter: NSObject {
    private var isMonitoring = false
    
    /// Delegate for receiving crash reports
    public weak var crashReportDelegate: CrashReportDelegate?
    
    /// Delegate for receiving hang reports
    public weak var hangReportDelegate: HangReportDelegate?

    /// Start crash monitoring
    public func startMonitoring() {
        guard !isMonitoring else {
            SwiftMoLogger.warn("MetricKit monitoring already active", tag: .crash)
            return
        }
        MXMetricManager.shared.add(self)
        isMonitoring = true
        SwiftMoLogger.info("MetricKit monitoring started", tag: .crash)
    }

    /// Stop crash monitoring
    public func stopMonitoring() {
        guard isMonitoring else {
            SwiftMoLogger.warn("MetricKit monitoring not active", tag: .crash)
            return
        }
        MXMetricManager.shared.remove(self)
        isMonitoring = false
        SwiftMoLogger.info("MetricKit monitoring stopped", tag: .crash)
    }
}

// MARK: - MXMetricManagerSubscriber

extension MetricKitCrashReporter: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        SwiftMoLogger.info("Received \(payloads.count) diagnostic payload(s)", tag: .crash)
        
        for payload in payloads {
            if let crashDiagnostics = payload.crashDiagnostics {
                SwiftMoLogger.info("Processing \(crashDiagnostics.count) crash diagnostic(s)", tag: .crash)
                handleCrashDiagnostics(crashDiagnostics)
            }
            
            if let hangDiagnostics = payload.hangDiagnostics {
                SwiftMoLogger.info("Processing \(hangDiagnostics.count) hang diagnostic(s)", tag: .performance)
                handleHangDiagnostics(hangDiagnostics)
            }
        }
    }
}

// MARK: - Private Methods

private extension MetricKitCrashReporter {
    func handleCrashDiagnostics(_ diagnostics: [MXCrashDiagnostic]) {
        for diagnostic in diagnostics {
            logCrashSummary(diagnostic)
            analyzeCrashCallStack(diagnostic.callStackTree)
            archiveCrashReport(diagnostic)
        }
    }
    
    func logCrashSummary(_ diagnostic: MXCrashDiagnostic) {
        SwiftMoLogger.error("🚨 CRASH DETECTED 🚨", tag: .crash)
        
        let summary = """
        App: \(diagnostic.applicationVersion)
        iOS: \(diagnostic.metaData.osVersion)
        Device: \(diagnostic.metaData.deviceType)
        """
        SwiftMoLogger.error(summary, tag: .crash)
        
        if let exceptionType = diagnostic.exceptionType {
            SwiftMoLogger.error("Exception: \(exceptionType)", tag: .crash)
        }
        
        if let signal = diagnostic.signal {
            SwiftMoLogger.error("Signal: \(signal)", tag: .crash)
        }
    }

    func analyzeCrashCallStack(_ callStackTree: MXCallStackTree) {
        let callStackData = callStackTree.jsonRepresentation()
        guard let jsonString = String(data: callStackData, encoding: .utf8) else {
            SwiftMoLogger.error("Unable to decode call stack", tag: .crash)
            return
        }

        SwiftMoLogger.info("🔍 Call Stack Analysis:", tag: .crash)
        printCrashPatternHints(in: jsonString)
        printUserBinaries(in: jsonString)
    }
    
    func archiveCrashReport(_ diagnostic: MXCrashDiagnostic) {
        let crashData = diagnostic.dictionaryRepresentation()
        let crashReport = createDetailedCrashReport(from: diagnostic)
        
        SwiftMoLogger.info("Crash report created", tag: .crash)
        
        // Convert for delegate compatibility
        let stringKeyCrashData: [String: Any] = Dictionary(uniqueKeysWithValues: 
            crashData.compactMap { key, value in
                guard let stringKey = key as? String else { return nil }
                return (stringKey, value)
            }
        )
        
        notifyCrashReportDelegates(crashReport, rawData: stringKeyCrashData)
        SwiftMoLogger.info("Crash report processing complete", tag: .crash)
    }
    
    func handleHangDiagnostics(_ diagnostics: [MXHangDiagnostic]) {
        for diagnostic in diagnostics {
            SwiftMoLogger.warn("🐌 HANG: \(diagnostic.hangDuration)ms", tag: .performance)
            
            let hangData = diagnostic.dictionaryRepresentation()
            let stringKeyHangData: [String: Any] = Dictionary(uniqueKeysWithValues: 
                hangData.compactMap { key, value in
                    guard let stringKey = key as? String else { return nil }
                    return (stringKey, value)
                }
            )
            
            notifyHangReportDelegates(diagnostic, rawData: stringKeyHangData)
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
        
        // Add call stack as JSON string
        let callStackData = diagnostic.callStackTree.jsonRepresentation()
        if let callStackString = String(data: callStackData, encoding: .utf8) {
            report["callStack"] = callStackString
        }
        
        return report
    }
    
    func notifyCrashReportDelegates(_ report: [String: Any], rawData: [String: Any]) {
        crashReportDelegate?.didReceiveCrashReport(report)
    }
    
    func notifyHangReportDelegates(_ diagnostic: MXHangDiagnostic, rawData: [String: Any]) {
        hangReportDelegate?.didReceiveHangReport(diagnostic, rawData: rawData)
    }
    

    func printCrashPatternHints(in callStackJSON: String) {
        if callStackJSON.contains("EXC_BAD_ACCESS") {
            SwiftMoLogger.warn("Memory access issue - likely deallocated memory", tag: .crash)
        } else if callStackJSON.contains("EXC_BREAKPOINT") {
            SwiftMoLogger.warn("Assertion failure or unhandled Swift error", tag: .crash)
        } else if callStackJSON.contains("EXC_CRASH") {
            SwiftMoLogger.warn("Process terminated - memory pressure or timeout", tag: .crash)
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
            let binariesList = userBinaries.joined(separator: ", ")
            SwiftMoLogger.info("User binaries in crash: \(binariesList)", tag: .crash)
        }
    }
    
    /// Trigger test crash for validation (DEBUG only)
    func triggerTestCrash() {
        #if DEBUG
        SwiftMoLogger.warn("Triggering test crash for validation", tag: .crash)
        fatalError("Test crash for MetricKit validation")
        #else
        SwiftMoLogger.warn("Test crashes only available in DEBUG builds", tag: .crash)
        #endif
    }
}