import Foundation

struct CrashReport: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let appVersion: String
    let osVersion: String
    let deviceModel: String
    let crashReason: String
    let stackTrace: String
    let additionalInfo: [String: String]
    
    init(timestamp: Date, appVersion: String, osVersion: String, deviceModel: String, crashReason: String, stackTrace: String, additionalInfo: [String: String] = [:]) {
        self.id = UUID()
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.crashReason = crashReason
        self.stackTrace = stackTrace
        self.additionalInfo = additionalInfo
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    var shortDescription: String {
        let lines = stackTrace.components(separatedBy: .newlines)
        return lines.first ?? "Unknown crash"
    }
}

// MARK: - Sample Data for Demo
extension CrashReport {
    static let sampleReports: [CrashReport] = [
        CrashReport(
            timestamp: Date().addingTimeInterval(-3600), // 1 hour ago
            appVersion: "1.0",
            osVersion: "iOS 17.0",
            deviceModel: "iPhone 15 Pro",
            crashReason: "EXC_BAD_ACCESS",
            stackTrace: """
            0   SwiftMoLoggerExampleApp     0x0000000104abc123 -[EnhancedMetricKitReporter triggerTestCrash] + 156
            1   SwiftMoLoggerExampleApp     0x0000000104abc456 -[MainViewController crashTestTapped:] + 89
            2   UIKitCore                   0x00000001a1234567 -[UIControl sendAction:to:forEvent:] + 64
            3   UIKitCore                   0x00000001a1234890 -[UIControl _sendActionsForEvents:withEvent:] + 124
            """,
            additionalInfo: [
                "Memory Usage": "45.2 MB",
                "Available Memory": "2.1 GB",
                "Battery Level": "78%"
            ]
        ),
        CrashReport(
            timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
            appVersion: "1.0",
            osVersion: "iOS 17.0",
            deviceModel: "iPhone 15 Pro",
            crashReason: "SIGABRT",
            stackTrace: """
            0   libsystem_kernel.dylib      0x00000001b1234567 __pthread_kill + 8
            1   libsystem_pthread.dylib     0x00000001b1234890 pthread_kill + 256
            2   libsystem_c.dylib          0x00000001b1234abc abort + 104
            3   SwiftMoLoggerExampleApp     0x0000000104abc789 NetworkManager.simulateNetworkError() + 67
            """,
            additionalInfo: [
                "Memory Usage": "52.8 MB",
                "Available Memory": "1.9 GB",
                "Network Status": "WiFi"
            ]
        )
    ]
}