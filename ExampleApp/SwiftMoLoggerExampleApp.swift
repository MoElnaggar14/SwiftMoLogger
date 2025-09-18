import SwiftUI
import SwiftMoLogger

@main
struct SwiftMoLoggerExampleApp: App {
    
    init() {
        configureLogging()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
    
    /// Configure SwiftMoLogger with multiple engines for comprehensive logging
    private func configureLogging() {
        SwiftMoLogger.info("🚀 SwiftMoLogger Example App launching...")
        
        // Add advanced logging engines for production-like setup
        #if DEBUG
        // Development engines - enhanced debugging
        SwiftMoLogger.addEngine(MemoryLogEngine(maxEntries: 500))
        SwiftMoLogger.addEngine(DebugLogEngine())
        SwiftMoLogger.info("🔧 Debug engines configured", tag: .debug)
        #endif
        
        // Production-ready engines
        SwiftMoLogger.addEngine(FileLogEngine())
        SwiftMoLogger.addEngine(AnalyticsLogEngine()) 
        
        SwiftMoLogger.info("⚙️ Logging system configured with \(SwiftMoLogger.engineCount) engines", tag: .lifecycle)
        SwiftMoLogger.info("📱 App ready for comprehensive logging demonstration")
    }
}

// MARK: - Advanced Custom Engines for Example App

/// Memory engine for debugging and log inspection
class MemoryLogEngine: LogEngine {
    private var logs: [LogEntry] = []
    private let maxEntries: Int
    private let queue = DispatchQueue(label: "memory.logger", attributes: .concurrent)
    
    struct LogEntry {
        let timestamp: Date
        let level: String
        let message: String
        let id = UUID()
    }
    
    init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }
    
    func info(message: String) {
        addLog(level: "INFO", message: message)
    }
    
    func warn(message: String) {
        addLog(level: "WARN", message: message)
    }
    
    func error(message: String) {
        addLog(level: "ERROR", message: message)
    }
    
    private func addLog(level: String, message: String) {
        queue.async(flags: .barrier) {
            let entry = LogEntry(timestamp: Date(), level: level, message: message)
            self.logs.append(entry)
            
            if self.logs.count > self.maxEntries {
                self.logs.removeFirst(self.logs.count - self.maxEntries)
            }
        }
    }
    
    func getAllLogs() -> [LogEntry] {
        return queue.sync { Array(logs) }
    }
    
    func getRecentLogs(count: Int = 10) -> [LogEntry] {
        return queue.sync { Array(logs.suffix(count)) }
    }
    
    func getErrorCount() -> Int {
        return queue.sync { logs.filter { $0.level == "ERROR" }.count }
    }
    
    func clear() {
        queue.async(flags: .barrier) {
            self.logs.removeAll()
        }
    }
}

/// File engine for persistent logging
class FileLogEngine: LogEngine {
    private let fileName: String
    private let queue = DispatchQueue(label: "file.logger", qos: .utility)
    private let dateFormatter: DateFormatter
    
    init() {
        // Use app documents directory for the log file
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.fileName = documentsPath.appendingPathComponent("swiftmologger_app.log").path
        
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }
    
    func info(message: String) {
        writeToFile(level: "INFO", message: message)
    }
    
    func warn(message: String) {
        writeToFile(level: "WARN", message: message)
    }
    
    func error(message: String) {
        writeToFile(level: "ERROR", message: message)
    }
    
    private func writeToFile(level: String, message: String) {
        queue.async {
            let logEntry = [
                "timestamp": self.dateFormatter.string(from: Date()),
                "level": level,
                "message": message,
                "thread": Thread.current.isMainThread ? "main" : "background"
            ]
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: logEntry),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                
                let logLine = "\(jsonString)\n"
                self.writeLogLine(logLine)
            }
        }
    }
    
    private func writeLogLine(_ logLine: String) {
        guard let data = logLine.data(using: .utf8) else { return }
        
        if FileManager.default.fileExists(atPath: fileName) {
            if let fileHandle = FileHandle(forWritingAtPath: fileName) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: fileName, contents: data, attributes: nil)
        }
    }
    
    func getLogFileURL() -> URL? {
        return URL(fileURLWithPath: fileName)
    }
    
    func getLogFileSize() -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileName),
              let fileSize = attributes[.size] as? Int64 else {
            return "0 bytes"
        }
        
        let formatter = ByteCountFormatter()
        return formatter.string(fromByteCount: fileSize)
    }
}

/// Analytics engine for error and performance tracking  
class AnalyticsLogEngine: LogEngine {
    private var errorCount = 0
    private var warningCount = 0
    private var infoCount = 0
    private let queue = DispatchQueue(label: "analytics.logger", attributes: .concurrent)
    
    func info(message: String) {
        queue.async(flags: .barrier) {
            self.infoCount += 1
        }
        
        // Track performance issues
        if message.contains("slow") || message.contains("performance") {
            trackEvent("performance_issue", properties: ["message": message])
        }
    }
    
    func warn(message: String) {
        queue.async(flags: .barrier) {
            self.warningCount += 1
        }
        trackEvent("warning", properties: ["message": message, "count": warningCount])
    }
    
    func error(message: String) {
        queue.async(flags: .barrier) {
            self.errorCount += 1
        }
        trackEvent("error", properties: ["message": message, "count": errorCount])
    }
    
    private func trackEvent(_ event: String, properties: [String: Any]) {
        print("📊 Analytics: \(event) - \(properties)")
    }
    
    func getMetrics() -> [String: Int] {
        return queue.sync {
            ["errors": errorCount, "warnings": warningCount, "info": infoCount]
        }
    }
    
    func reset() {
        queue.async(flags: .barrier) {
            self.errorCount = 0
            self.warningCount = 0
            self.infoCount = 0
        }
    }
}

/// Debug engine with enhanced console output
class DebugLogEngine: LogEngine {
    private let dateFormatter: DateFormatter
    
    init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
    }
    
    func info(message: String) {
        #if DEBUG
        let timestamp = dateFormatter.string(from: Date())
        let thread = Thread.current.isMainThread ? "🔵" : "🟠"
        print("\(thread) [\(timestamp)] ℹ️ \(message)")
        #endif
    }
    
    func warn(message: String) {
        #if DEBUG
        let timestamp = dateFormatter.string(from: Date())
        let thread = Thread.current.isMainThread ? "🔵" : "🟠"
        print("\(thread) [\(timestamp)] ⚠️ \(message)")
        #endif
    }
    
    func error(message: String) {
        #if DEBUG
        let timestamp = dateFormatter.string(from: Date())
        let thread = Thread.current.isMainThread ? "🔵" : "🟠"
        print("\(thread) [\(timestamp)] 🚨 \(message)")
        #endif
    }
}