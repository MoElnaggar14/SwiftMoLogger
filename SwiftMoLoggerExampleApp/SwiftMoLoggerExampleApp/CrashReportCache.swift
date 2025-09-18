import Foundation
import UIKit
import SwiftMoLogger

class CrashReportCache {
    static let shared = CrashReportCache()
    
    private let cacheKey = "CachedCrashReports"
    private let userDefaults = UserDefaults.standard
    
    private init() {
        // Load sample data for demo purposes
        if getCachedReports().isEmpty {
            cacheReports(CrashReport.sampleReports)
        }
    }
    
    // MARK: - Cache Management
    
    func cacheReport(_ report: CrashReport) {
        var reports = getCachedReports()
        reports.insert(report, at: 0) // Add new reports at the beginning
        
        // Keep only the last 50 reports
        if reports.count > 50 {
            reports = Array(reports.prefix(50))
        }
        
        cacheReports(reports)
        
        SwiftMoLogger.info(message: "Cached new crash report", tag: LogTag.Data.cache)
    }
    
    func cacheReports(_ reports: [CrashReport]) {
        do {
            let data = try JSONEncoder().encode(reports)
            userDefaults.set(data, forKey: cacheKey)
            SwiftMoLogger.info(message: "Cached \(reports.count) crash reports", tag: LogTag.Data.cache)
        } catch {
            SwiftMoLogger.error(message: "Failed to cache crash reports: \(error)", tag: LogTag.Data.cache)
        }
    }
    
    func getCachedReports() -> [CrashReport] {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            return []
        }
        
        do {
            let reports = try JSONDecoder().decode([CrashReport].self, from: data)
            return reports
        } catch {
            SwiftMoLogger.error(message: "Failed to decode cached crash reports: \(error)", tag: LogTag.Data.cache)
            return []
        }
    }
    
    func clearCache() {
        userDefaults.removeObject(forKey: cacheKey)
        SwiftMoLogger.info(message: "Cleared crash report cache", tag: LogTag.Data.cache)
    }
    
    func getCacheSize() -> String {
        guard let data = userDefaults.data(forKey: cacheKey) else {
            return "0 KB"
        }
        
        let bytes = data.count
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
    
    // MARK: - Demo Functionality
    
    func addSampleCrashReport() {
        let newReport = CrashReport(
            timestamp: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            osVersion: UIDevice.current.systemVersion,
            deviceModel: UIDevice.current.model,
            crashReason: "EXC_BREAKPOINT",
            stackTrace: """
            0   SwiftMoLoggerExampleApp     0x0000000104abc123 EnhancedMetricKitReporter.triggerTestCrash() + 156
            1   SwiftMoLoggerExampleApp     0x0000000104abc456 MainViewController.crashTestTapped() + 212
            2   SwiftMoLoggerExampleApp     0x0000000104abc789 closure #2 in MainViewController.crashTestTapped() + 280
            3   UIKitCore                   0x00000001a1234567 -[UIAlertController _invokeHandlersForAction:] + 80
            """,
            additionalInfo: [
                "Memory Usage": "\(String(format: "%.1f", Double.random(in: 40...80))) MB",
                "Available Memory": "\(String(format: "%.1f", Double.random(in: 1.5...3.0))) GB",
                "Battery Level": "\(Int.random(in: 20...100))%",
                "Network Status": Bool.random() ? "WiFi" : "Cellular"
            ]
        )
        
        cacheReport(newReport)
    }
}