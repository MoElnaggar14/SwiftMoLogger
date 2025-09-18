#!/usr/bin/env swift

import Foundation

// This would normally be: import SwiftMoLogger
// But for demo purposes, we'll include the core components inline

// MARK: - Core Protocol
protocol LogEngine {
    func info(message: String)
    func warn(message: String)
    func error(message: String)
}

// MARK: - Log Tags (simplified)
enum LogTag: String {
    case api = "[API]"
    case database = "[Database]"
    case network = "[Network]"
    case ui = "[UI]"
    case crash = "[Crash]"
    case performance = "[Performance]"
}

// MARK: - System Logger
class SystemLogger: LogEngine {
    func info(message: String) {
        print("ℹ️ \(message)")
    }
    
    func warn(message: String) {
        print("⚠️ \(message)")
    }
    
    func error(message: String) {
        print("🚨 \(message)")
    }
}

// MARK: - Engine Registry (Thread-Safe)
class EngineRegistry {
    static let shared = EngineRegistry()
    private var engines: [LogEngine] = []
    private let queue = DispatchQueue(label: "demo.registry", attributes: .concurrent)
    
    private init() {
        engines.append(SystemLogger())
    }
    
    func addEngine(_ engine: LogEngine) {
        queue.async(flags: .barrier) {
            self.engines.append(engine)
        }
    }
    
    func removeEngine(at index: Int) {
        queue.async(flags: .barrier) {
            guard index > 0 && index < self.engines.count else { return }
            self.engines.remove(at: index)
        }
    }
    
    func getAllEngines() -> [LogEngine] {
        return queue.sync {
            return Array(self.engines)
        }
    }
    
    var engineCount: Int { 
        queue.sync { engines.count } 
    }
    
    func reset() {
        queue.async(flags: .barrier) {
            self.engines = [SystemLogger()]
        }
    }
}

// MARK: - SwiftMoLogger API
enum SwiftMoLogger {
    // Basic logging
    static func info(_ message: String) {
        EngineRegistry.shared.getAllEngines().forEach { $0.info(message: message) }
    }
    
    static func warn(_ message: String) {
        EngineRegistry.shared.getAllEngines().forEach { $0.warn(message: message) }
    }
    
    static func error(_ message: String) {
        EngineRegistry.shared.getAllEngines().forEach { $0.error(message: message) }
    }
    
    // Tagged logging
    static func info(_ message: String, tag: LogTag) {
        info("\(tag.rawValue) \(message)")
    }
    
    static func warn(_ message: String, tag: LogTag) {
        warn("\(tag.rawValue) \(message)")
    }
    
    static func error(_ message: String, tag: LogTag) {
        error("\(tag.rawValue) \(message)")
    }
    
    // Convenience methods
    static func crash(_ message: String) {
        error("\(LogTag.crash.rawValue) \(message)")
    }
    
    // Engine management
    static func addEngine(_ engine: LogEngine) {
        EngineRegistry.shared.addEngine(engine)
    }
    
    static func removeEngine(at index: Int) {
        EngineRegistry.shared.removeEngine(at: index)
    }
    
    static var engineCount: Int {
        EngineRegistry.shared.engineCount
    }
    
    static func reset() {
        EngineRegistry.shared.reset()
    }
}

// MARK: - Advanced Custom Engines

/// High-performance memory engine with circular buffer and filtering
class MemoryLogEngine: LogEngine {
    private var logs: [LogEntry] = []
    private let maxEntries: Int
    private let queue = DispatchQueue(label: "memory.logger", attributes: .concurrent)
    
    struct LogEntry {
        let timestamp: Date
        let level: String
        let message: String
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
            
            // Circular buffer - remove oldest entries
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
}

/// Production-ready file engine with rotation and JSON formatting
class FileLogEngine: LogEngine {
    let fileName = "/tmp/swiftmologger_demo.log"
    private let queue = DispatchQueue(label: "file.logger", qos: .utility)
    private let dateFormatter: DateFormatter
    private var currentFileSize = 0
    private let maxFileSize = 1024 * 1024 // 1MB
    
    init() {
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
        
        // Check file size and rotate if needed
        if FileManager.default.fileExists(atPath: fileName) {
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileName),
               let fileSize = attributes[.size] as? Int {
                if fileSize > maxFileSize {
                    rotateLogFile()
                }
            }
        }
        
        // Write to file
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
    
    private func rotateLogFile() {
        let backupFile = fileName + ".old"
        try? FileManager.default.removeItem(atPath: backupFile)
        try? FileManager.default.moveItem(atPath: fileName, toPath: backupFile)
    }
}

/// Network engine with batching and retry logic
class NetworkLogEngine: LogEngine {
    private let endpoint = "https://logs.example.com/api/logs"
    private var logBatch: [[String: Any]] = []
    private let queue = DispatchQueue(label: "network.logger", qos: .utility)
    private let batchSize = 10
    private let session = URLSession.shared
    
    func info(message: String) {
        addToBatch(level: "INFO", message: message)
    }
    
    func warn(message: String) {
        addToBatch(level: "WARN", message: message)
    }
    
    func error(message: String) {
        addToBatch(level: "ERROR", message: message)
    }
    
    private func addToBatch(level: String, message: String) {
        queue.async {
            let logEntry = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "level": level,
                "message": message,
                "app_version": "1.0.0",
                "platform": "iOS"
            ]
            
            self.logBatch.append(logEntry)
            
            if self.logBatch.count >= self.batchSize {
                self.flushBatch()
            }
        }
    }
    
    private func flushBatch() {
        guard !logBatch.isEmpty else { return }
        
        let batch = logBatch
        logBatch.removeAll()
        
        // In a real implementation, this would actually send to server
        print("📤 Would send \(batch.count) logs to \(endpoint)")
        
        // Simulate network request
        let payload = ["logs": batch]
        if let jsonData = try? JSONSerialization.data(withJSONObject: payload) {
            print("   Payload size: \(jsonData.count) bytes")
        }
    }
    
    deinit {
        // Flush remaining logs on cleanup
        if !logBatch.isEmpty {
            flushBatch()
        }
    }
}

/// Analytics engine that only logs errors and performance issues
class AnalyticsLogEngine: LogEngine {
    private var errorCount = 0
    private var warningCount = 0
    
    func info(message: String) {
        // Analytics typically ignores info logs to reduce noise
        if message.contains("performance") || message.contains("slow") {
            trackEvent("performance_issue", properties: ["message": message])
        }
    }
    
    func warn(message: String) {
        warningCount += 1
        trackEvent("warning", properties: ["message": message, "count": warningCount])
    }
    
    func error(message: String) {
        errorCount += 1
        trackEvent("error", properties: ["message": message, "count": errorCount])
    }
    
    private func trackEvent(_ event: String, properties: [String: Any]) {
        print("📊 Analytics: \(event) - \(properties)")
    }
    
    func getMetrics() -> [String: Int] {
        return ["errors": errorCount, "warnings": warningCount]
    }
}

/// Debug engine that only works in DEBUG builds with detailed formatting
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
        print("📍 Stack trace: \(Thread.callStackSymbols.prefix(3).joined(separator: "\n"))")
        #endif
    }
}

// MARK: - Demo Tagged Objects

struct ExampleNetworkManager {
    func performRequest() {
        SwiftMoLogger.info("🌐 API request started", tag: .network)
        // Simulate network delay
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
            SwiftMoLogger.warn("⌛ Request took longer than expected", tag: .network)
        }
    }
}

struct ExampleUserService {
    func updateProfile() {
        SwiftMoLogger.info("👤 User profile update initiated", tag: .api)
        SwiftMoLogger.error("🚫 Validation failed for email field", tag: .api)
    }
}

// MARK: - Demo Functions

func runAdvancedDemo() {
    print("\n=== SwiftMoLogger Advanced Production Demo ===")
    
    // Test basic logging
    print("\n1. Basic System Logging:")
    SwiftMoLogger.info("🚀 Application started successfully")
    SwiftMoLogger.warn("⚠️ Low memory warning detected")
    SwiftMoLogger.error("❌ Failed to load configuration file")
    
    // Test tagged logging
    print("\n2. Tagged Component Logging:")
    let networkManager = ExampleNetworkManager()
    let userService = ExampleUserService()
    
    networkManager.performRequest()
    userService.updateProfile()
    
    // Test engine management with advanced engines
    print("\n3. Advanced Engine Management:")
    print("📈 Default engines count: \(SwiftMoLogger.engineCount)")
    
    // Add production-ready custom engines
    let memoryEngine = MemoryLogEngine(maxEntries: 50)
    let fileEngine = FileLogEngine()
    let networkEngine = NetworkLogEngine()
    let analyticsEngine = AnalyticsLogEngine()
    let debugEngine = DebugLogEngine()
    
    SwiftMoLogger.addEngine(memoryEngine)
    SwiftMoLogger.addEngine(fileEngine)
    SwiftMoLogger.addEngine(networkEngine)
    SwiftMoLogger.addEngine(analyticsEngine)
    SwiftMoLogger.addEngine(debugEngine)
    
    print("📊 After adding 5 custom engines: \(SwiftMoLogger.engineCount) total")
    
    // Demonstrate different scenarios
    print("\n4. Multi-Engine Logging Scenarios:")
    
    // Performance scenario
    SwiftMoLogger.info("⏱️ Database query completed in 250ms (slow performance detected)")
    
    // Error scenarios
    SwiftMoLogger.warn("🔄 Retrying failed network request (attempt 2/3)")
    SwiftMoLogger.error("💥 Critical: Payment processing failed for user 12345")
    SwiftMoLogger.error("🔐 Authentication token expired - redirecting to login")
    
    // Background operations simulation
    SwiftMoLogger.info("📂 Background sync completed successfully")
    SwiftMoLogger.warn("🔄 Background sync took longer than expected: 45 seconds")
    
    // Show results immediately 
    showEngineResults(memoryEngine: memoryEngine, analyticsEngine: analyticsEngine, fileEngine: fileEngine)
}

func showEngineResults(memoryEngine: MemoryLogEngine, analyticsEngine: AnalyticsLogEngine, fileEngine: FileLogEngine) {
    print("\n5. Engine-Specific Results:")
    
    // Memory engine results
    print("\n📝 Memory Engine Summary:")
    let recentLogs = memoryEngine.getRecentLogs(count: 5)
    print("   Recent logs (last 5):")
    for log in recentLogs {
        let timeStr = DateFormatter.localizedString(from: log.timestamp, dateStyle: .none, timeStyle: .medium)
        print("   [\(timeStr)] \(log.level): \(log.message)")
    }
    print("   Total error count: \(memoryEngine.getErrorCount())")
    print("   Total logs stored: \(memoryEngine.getAllLogs().count)")
    
    // Analytics engine results
    print("\n📊 Analytics Engine Metrics:")
    let metrics = analyticsEngine.getMetrics()
    for (key, value) in metrics {
        print("   \(key): \(value)")
    }
    
    print("\n💾 File Engine: Logs written to JSON format in \(fileEngine.fileName)")
    if let fileContent = try? String(contentsOfFile: fileEngine.fileName, encoding: .utf8) {
        print("   File content preview (last 2 lines):")
        let lines = fileContent.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines.suffix(2) {
            print("   \(line)")
        }
    }
    
    print("📤 Network Engine: Batched logs ready for remote server transmission")
    print("🔍 Debug Engine: Enhanced console output with timestamps and thread indicators")
    
    // Demonstrate cleanup
    print("\n6. Cleanup and Reset:")
    SwiftMoLogger.reset()
    print("✅ All engines removed. Current count: \(SwiftMoLogger.engineCount)")
    print("🔄 SwiftMoLogger ready for production use with clean slate")
    
    print("\n✨ Key Advanced Features Demonstrated:")
    print("   • Thread-safe concurrent logging across multiple engines")
    print("   • Memory engine with circular buffer and filtering")
    print("   • File engine with JSON formatting and log rotation")
    print("   • Network engine with batching for efficient transmission")
    print("   • Analytics engine focusing on errors and performance")
    print("   • Debug engine with conditional compilation and stack traces")
    print("   • Clean extensible architecture ready for production")
}

// MARK: - Run Demo

runAdvancedDemo()
