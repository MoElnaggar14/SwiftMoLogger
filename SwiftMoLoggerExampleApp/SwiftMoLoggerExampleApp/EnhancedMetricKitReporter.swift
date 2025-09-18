import Foundation
import UIKit
import MetricKit
import SwiftMoLogger

/// Example app crash reporter that demonstrates UI integration
/// This shows how to integrate the production MetricKitCrashReporter with UI features
/// Focus: Demo/UI layer for crash reporting functionality
class EnhancedMetricKitReporter: NSObject {
    // Use the production crash reporter as the foundation
    private let productionReporter = MetricKitCrashReporter()
    
    override init() {
        super.init()
        
        // Set this class as the delegate to receive crash reports
        productionReporter.crashReportDelegate = self
        
        // Add some sample crash reports for UI demonstration
        addSampleCrashReports()
    }
    
    /// Start monitoring for crash diagnostics (delegates to production reporter)
    func startMonitoring() {
        productionReporter.startMonitoring()
        SwiftMoLogger.info(message: "Example app crash monitoring started with UI integration", tag: LogTag.System.crash)
    }
    
    /// Stop monitoring for crash diagnostics (delegates to production reporter)
    func stopMonitoring() {
        productionReporter.stopMonitoring()
        SwiftMoLogger.info(message: "Example app crash monitoring stopped", tag: LogTag.System.crash)
    }
    
    /// Trigger a test crash (DEBUG only) - creates demo crash report for UI
    func triggerTestCrash() {
        #if DEBUG
        SwiftMoLogger.warn(message: "Triggering test crash for UI demonstration", tag: LogTag.System.crash)
        
        // Store a demo crash report for the UI (before actual crash)
        storePendingCrashReport()
        
        // Delegate to production reporter for the actual crash
        productionReporter.triggerTestCrash()
        #else
        SwiftMoLogger.warn(message: "Test crash is only available in DEBUG builds", tag: LogTag.System.crash)
        #endif
    }
    
    /// Store a pending crash report (called before crash)
    private func storePendingCrashReport() {
        let crashReport = CrashReport(
            timestamp: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            crashReason: "Test Crash (fatalError): Intentional crash for demonstration",
            stackTrace: "Test crash triggered by user via Crash Test button",
            additionalInfo: ["source": "user_triggered", "type": "test_crash"]
        )
        
        // Store the report that will be available after restart
        CrashReportCache.shared.cacheReport(crashReport)
        SwiftMoLogger.info(message: "Pre-crash report stored for post-restart viewing", tag: LogTag.System.crash)
    }
    
    /// Add some sample crash reports for demonstration purposes
    private func addSampleCrashReports() {
        let existingReports = CrashReportCache.shared.getCachedReports()
        
        // Only add samples if no reports exist
        guard existingReports.isEmpty else { return }
        
        let sampleReports = [
            CrashReport(
                timestamp: Date().addingTimeInterval(-86400), // 1 day ago
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                osVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.current.model,
                crashReason: "Segmentation fault (SIGSEGV): Invalid memory access",
                stackTrace: generateSampleCrashReport(type: "SIGSEGV", description: "Memory access violation"),
                additionalInfo: ["type": "SIGSEGV", "source": "sample_data"]
            ),
            CrashReport(
                timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
                appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
                osVersion: UIDevice.current.systemVersion,
                deviceModel: UIDevice.current.model,
                crashReason: "Abort (SIGABRT): Process terminated by system",
                stackTrace: generateSampleCrashReport(type: "SIGABRT", description: "Assertion failure"),
                additionalInfo: ["type": "SIGABRT", "source": "sample_data"]
            )
        ]
        
        for report in sampleReports {
            CrashReportCache.shared.cacheReport(report)
        }
        
        SwiftMoLogger.info(message: "Added \(sampleReports.count) sample crash reports for demonstration", tag: LogTag.System.crash)
    }
    
    /// Generate a realistic sample crash report
    private func generateSampleCrashReport(type: String = "fatalError", description: String = "Test crash") -> String {
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return """
        🚨 SwiftMoLogger Crash Report 🚨
        
        📍 CRASH SUMMARY
        =====================================
        Timestamp: \(formatter.string(from: timestamp))
        App Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        iOS Version: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model) (\(UIDevice.current.name))
        Signal: \(type)
        Description: \(description)
        
        🔍 TECHNICAL DETAILS
        =====================================
        Exception Type: \(type)
        Exception Code: 0x0000000000000000
        Crashed Thread: 0 (Main Thread)
        
        📋 CALL STACK ANALYSIS
        =====================================
        Thread 0 (Main Thread):
        0  SwiftMoLoggerExampleApp    0x0000000104567890 triggerTestCrash() + 64
        1  SwiftMoLoggerExampleApp    0x0000000104567234 @objc crashTestTapped + 52
        2  UIKit                      0x00000001a2345678 -[UIApplication sendAction:to:from:forEvent:] + 96
        3  UIKit                      0x00000001a2345123 -[UIControl sendAction:to:forEvent:] + 128
        4  SwiftMoLoggerExampleApp    0x0000000104556789 MainViewController.viewDidLoad() + 256
        5  UIKit                      0x00000001a2334567 -[UIViewController _sendViewDidLoadWithAppearanceProxyObjectTaggingEnabled] + 84
        
        🔧 CRASH PATTERN ANALYSIS
        =====================================
        ⚠️  This appears to be an intentional crash for testing purposes
        ✅  MetricKit crash reporting is working correctly
        📱  System-level crash collection is active
        
        💡 RECOMMENDATIONS
        =====================================
        • This was a test crash triggered by the user
        • Real crashes would show actual memory issues or exceptions
        • MetricKit provides more detailed system diagnostics in production
        • Call stack shows user code path leading to crash
        
        📊 MEMORY INFORMATION
        =====================================
        Memory Usage: ~50MB (estimated)
        Memory Pressure: None
        Available Memory: >1GB
        
        🏷️  BINARY INFORMATION
        =====================================
        User Binaries in Crash:
        • SwiftMoLoggerExampleApp (Main executable)
        
        System Frameworks:
        • UIKit (User interface framework)
        • Foundation (Core framework)
        • MetricKit (Crash reporting framework)
        
        =====================================
        End of Crash Report
        Generated by SwiftMoLogger v1.0
        Created by Mohammed Elnaggar (@MoElnaggar14)
        =====================================
        """
    }
}

// MARK: - CrashReportDelegate
extension EnhancedMetricKitReporter: CrashReportDelegate {
    func didReceiveCrashReport(_ report: [String: Any]) {
        SwiftMoLogger.info(message: "📨 Received crash report from production reporter", tag: LogTag.System.crash)
        
        // Convert production crash report to UI-friendly format and cache it
        let uiCrashReport = convertProductionReportToUIFormat(report)
        CrashReportCache.shared.cacheReport(uiCrashReport)
        
        SwiftMoLogger.info(message: "📱 Crash report stored for in-app viewing", tag: LogTag.System.crash)
    }
    
    private func convertProductionReportToUIFormat(_ report: [String: Any]) -> CrashReport {
        // Parse timestamp from ISO8601 string or Date object
        let timestamp: Date
        if let timestampString = report["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: timestampString) ?? Date()
        } else {
            timestamp = (report["timestamp"] as? Date) ?? Date()
        }
        
        // Build crash reason from production report data
        var crashReason = "Unknown crash"
        if let signalDescription = report["signalDescription"] as? String {
            crashReason = signalDescription
        } else if let exceptionType = report["exceptionType"] as? String {
            crashReason = "Exception: \(exceptionType)"
        }
        
        // Build additional info from production report fields
        var additionalInfo: [String: String] = [:]
        if let exceptionType = report["exceptionType"] as? String {
            additionalInfo["exceptionType"] = exceptionType
        }
        if let exceptionCode = report["exceptionCode"] as? String {
            additionalInfo["exceptionCode"] = exceptionCode
        }
        if let signal = report["signal"] as? String {
            additionalInfo["signal"] = signal
        }
        if let crashId = report["crashId"] as? String {
            additionalInfo["crashId"] = crashId
        }
        additionalInfo["source"] = "production_reporter"
        
        return CrashReport(
            timestamp: timestamp,
            appVersion: report["appVersion"] as? String ?? "Unknown",
            osVersion: report["osVersion"] as? String ?? "Unknown",
            deviceModel: report["deviceType"] as? String ?? "Unknown", // Note: production uses "deviceType"
            crashReason: crashReason,
            stackTrace: report["callStack"] as? String ?? "No stack trace available", // Note: production uses "callStack"
            additionalInfo: additionalInfo
        )
    }
}
