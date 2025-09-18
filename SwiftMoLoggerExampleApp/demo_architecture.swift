#!/usr/bin/env swift

import Foundation

// MARK: - Architecture Demo Script
// This script demonstrates the clean separation between production and UI layers

print("""
🏗️  SwiftMoLogger Crash Reporting Architecture Demo
==================================================

This demonstrates how the refactored architecture provides clean separation
between production-ready crash reporting and UI/demo functionality.

""")

// MARK: - Production Layer Simulation

class MockProductionCrashReporter {
    weak var crashReportDelegate: CrashReportDelegate?
    
    func startMonitoring() {
        print("🔧 PRODUCTION: MetricKitCrashReporter.startMonitoring()")
        print("   ✅ Subscribed to MXMetricManager")
        print("   ✅ Crash monitoring active")
        print("   ✅ Signal detection enabled")
        print("   ✅ Call stack analysis ready")
        print("")
    }
    
    func triggerTestCrash() {
        print("🚨 PRODUCTION: Triggering test crash...")
        print("   📊 Analyzing crash patterns...")
        print("   🔍 Extracting call stack...")
        print("   📋 Creating production crash report...")
        
        // Simulate creating a production crash report
        let productionReport: [String: Any] = [
            "timestamp": "2024-01-15T10:30:00Z",
            "crashId": "crash_abc123",
            "appVersion": "1.0.0",
            "osVersion": "17.2",
            "deviceType": "iPhone15,2",
            "exceptionType": "SIGABRT",
            "exceptionCode": "0x0000000000000000",
            "signal": "6",
            "signalDescription": "Abort (SIGABRT): Process terminated by system",
            "callStack": """
            Thread 0 (Main Thread):
            0  SwiftMoLoggerExampleApp    0x0000000104567890 triggerTestCrash() + 64
            1  SwiftMoLoggerExampleApp    0x0000000104567234 @objc crashTestTapped + 52
            2  UIKit                      0x00000001a2345678 -[UIApplication sendAction:to:from:forEvent:] + 96
            """
        ]
        
        print("   ✅ Production report ready")
        print("   📤 Notifying delegates...")
        
        // Notify delegate (this would be the UI layer in real app)
        crashReportDelegate?.didReceiveCrashReport(productionReport)
        print("")
    }
}

// MARK: - UI/Demo Layer Simulation

protocol CrashReportDelegate: AnyObject {
    func didReceiveCrashReport(_ report: [String: Any])
}

class MockDemoUIReporter: CrashReportDelegate {
    private let productionReporter = MockProductionCrashReporter()
    
    init() {
        print("🎨 UI LAYER: EnhancedMetricKitReporter initialized")
        print("   🔗 Setting self as delegate for production reporter")
        productionReporter.crashReportDelegate = self
        print("   📱 UI crash report cache initialized")
        print("   🎯 Sample data added for demonstration")
        print("")
    }
    
    func startMonitoring() {
        print("🎨 UI LAYER: Delegating startMonitoring() to production layer")
        productionReporter.startMonitoring()
    }
    
    func triggerTestCrash() {
        print("🎨 UI LAYER: Delegating triggerTestCrash() to production layer")
        productionReporter.triggerTestCrash()
    }
    
    // MARK: - CrashReportDelegate
    func didReceiveCrashReport(_ report: [String: Any]) {
        print("🎨 UI LAYER: Received crash report from production reporter")
        print("   📨 Converting production format to UI format...")
        
        let uiReport = convertProductionReportToUIFormat(report)
        
        print("   💾 Caching report for in-app viewing...")
        print("   📱 UI crash report stored successfully")
        print("   🎯 Report available in crash reports viewer")
        print("")
        
        print("✨ CONVERSION RESULT:")
        print("   📅 Timestamp: \(uiReport.timestamp)")
        print("   📱 App Version: \(uiReport.appVersion)")
        print("   🔧 Device: \(uiReport.deviceModel)")
        print("   ⚠️  Reason: \(uiReport.crashReason)")
        print("   📊 Stack Trace: \(String(uiReport.stackTrace.prefix(100)))...")
        print("")
    }
    
    private func convertProductionReportToUIFormat(_ report: [String: Any]) -> UIFriendlyCrashReport {
        let timestamp: Date
        if let timestampString = report["timestamp"] as? String {
            let formatter = ISO8601DateFormatter()
            timestamp = formatter.date(from: timestampString) ?? Date()
        } else {
            timestamp = Date()
        }
        
        let crashReason = report["signalDescription"] as? String ?? "Unknown crash"
        
        return UIFriendlyCrashReport(
            timestamp: timestamp,
            appVersion: report["appVersion"] as? String ?? "Unknown",
            osVersion: report["osVersion"] as? String ?? "Unknown",
            deviceModel: report["deviceType"] as? String ?? "Unknown",
            crashReason: crashReason,
            stackTrace: report["callStack"] as? String ?? "No stack trace available"
        )
    }
}

struct UIFriendlyCrashReport {
    let timestamp: Date
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let crashReason: String
    let stackTrace: String
}

// MARK: - Demo Execution

print("🚀 DEMO: Initializing crash reporting system...")
print(String(repeating: "=", count: 60))
print("")

let demoReporter = MockDemoUIReporter()

print("🚀 DEMO: Starting crash monitoring...")
print(String(repeating: "=", count: 60))
print("")

demoReporter.startMonitoring()

print("🚀 DEMO: Triggering test crash to show data flow...")
print(String(repeating: "=", count: 60))
print("")

demoReporter.triggerTestCrash()

print("🎉 DEMO COMPLETE!")
print(String(repeating: "=", count: 60))
print("")

print("""
📋 ARCHITECTURE BENEFITS DEMONSTRATED:

✅ Clean Separation:
   • Production layer handles all MetricKit complexity
   • UI layer focuses only on presentation and caching
   • Zero code duplication between layers

✅ Maintainability:
   • Single source of truth for crash reporting logic
   • UI changes don't affect production reliability
   • Easy to test components independently

✅ Production Ready:
   • MetricKitCrashReporter is robust and extensible
   • Clear distinction between production and demo code
   • Delegates enable easy integration with external services

✅ Extensibility:
   • Production reporter supports multiple delegates
   • UI layer can be customized without affecting core logic
   • Easy to add new features like Firebase integration

""")

print("🔗 Next Steps:")
print("   1. Use MetricKitCrashReporter directly in production apps")
print("   2. Reference EnhancedMetricKitReporter for UI integration patterns")
print("   3. Implement CrashReportDelegate for external service integration")
print("")
print("Created by Mohammed Elnaggar (@MoElnaggar14)")
print("SwiftMoLogger v1.0")