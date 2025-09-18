import UIKit
import SwiftMoLogger

// MARK: - Crash Report Data Model
// CrashReport struct is defined in CrashReport.swift

// MARK: - Crash Report Storage

class CrashReportStorage {
    static let shared = CrashReportStorage()
    
    private let userDefaults = UserDefaults.standard
    private let storageKey = "stored_crash_reports"
    private var crashReports: [CrashReport] = []
    
    private init() {
        loadCrashReports()
    }
    
    func storeCrashReport(_ crashReport: CrashReport) {
        crashReports.append(crashReport)
        saveCrashReports()
        
        SwiftMoLogger.info(message: "Crash report stored in app (ID: \(crashReport.id))", tag: LogTag.System.crash)
    }
    
    func getAllCrashReports() -> [CrashReport] {
        return crashReports.sorted { $0.timestamp > $1.timestamp }
    }
    
    func clearAllCrashReports() {
        crashReports.removeAll()
        saveCrashReports()
        
        SwiftMoLogger.info(message: "All crash reports cleared from storage", tag: LogTag.System.crash)
    }
    
    private func loadCrashReports() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CrashReport].self, from: data) else {
            return
        }
        
        crashReports = decoded
        
        SwiftMoLogger.info(message: "Loaded \(crashReports.count) crash reports from storage", tag: LogTag.System.crash)
    }
    
    private func saveCrashReports() {
        if let encoded = try? JSONEncoder().encode(crashReports) {
            userDefaults.set(encoded, forKey: storageKey)
            SwiftMoLogger.info(message: "Crash reports saved to storage", tag: LogTag.Data.userdefaults)
        }
    }
}


