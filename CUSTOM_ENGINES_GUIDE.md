# SwiftMoLogger Custom Engines Guide 🔧

This guide demonstrates how to create custom logging engines using SwiftMoLogger's new extensible, Domain-Driven Design (DDD) and Protocol-Oriented Programming (POP) architecture.

## 🏗️ Architecture Overview

SwiftMoLogger now follows a clean layered architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                      Application Layer                       │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              SwiftMoLogger API                      │    │
│  │  • Static convenience methods                       │    │
│  │  • Backward compatibility                           │    │
│  │  • Builder pattern configuration                    │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  ┌─────────────────────────────────────────────────────┐    │
│  │            LoggingManager (Service)                 │    │
│  │  • EngineRegistry                                   │    │
│  │  • Middleware processing                            │    │
│  │  • Thread-safe operations                           │    │
│  └─────────────────────────────────────────────────────┘    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Domain Entities                        │    │
│  │  • LogEntry, LogLevel, LogMetadata                  │    │
│  │  • LogContext, DeviceInfo                           │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│                    Infrastructure Layer                      │
│  ┌─────────────────────────────────────────────────────┐    │
│  │          Concrete Engine Implementations            │    │
│  │  • ConsoleLogEngine, FileLogEngine                  │    │
│  │  • NetworkLogEngine, MemoryLogEngine                │    │
│  │  • Custom engines (your implementations)            │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## 🛠️ Creating Custom Engines

### Basic Custom Engine

Here's how to create a simple custom logging engine:

```swift
import SwiftMoLogger

/// Custom engine that logs to a database
public class DatabaseLogEngine: LogEngine {
    public let id: String = "database"
    public let name: String = "Database"
    public var isEnabled: Bool = true
    public var minimumLevel: LogLevel = .info
    public var formatter: LogFormatter = StandardLogFormatter()
    public var filter: LogFilter?
    
    private let databaseService: DatabaseService
    
    public init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }
    
    public func log(_ entry: LogEntry) {
        guard isEnabled && entry.level >= minimumLevel else { return }
        
        // Apply filter if present
        if let filter = filter, !filter.shouldLog(entry) {
            return
        }
        
        // Format the message
        let formattedMessage = formatter.format(entry)
        
        // Store in database
        Task {
            await databaseService.store(
                logEntry: entry,
                formattedMessage: formattedMessage
            )
        }
    }
    
    public func configure(with config: EngineConfiguration) {
        self.minimumLevel = config.minimumLevel
        self.isEnabled = config.isEnabled
        
        // Handle custom settings
        if let dbConfig = config.customSettings["database"] as? DatabaseConfig {
            databaseService.configure(dbConfig)
        }
    }
    
    public func flush() async {
        await databaseService.flush()
    }
    
    public func close() {
        databaseService.close()
    }
}

// Usage
let dbEngine = DatabaseLogEngine(databaseService: myDatabaseService)
SwiftMoLogger.addEngine(dbEngine)
```

### Advanced Custom Engine with Configuration

```swift
/// Slack notification engine for critical errors
public class SlackLogEngine: LogEngine {
    public let id: String = "slack"
    public let name: String = "Slack"
    public var isEnabled: Bool = true
    public var minimumLevel: LogLevel = .error // Only log errors and critical
    public var formatter: LogFormatter = JSONLogFormatter()
    public var filter: LogFilter?
    
    private let webhookURL: URL
    private let channel: String
    private let session: URLSession
    private let queue = DispatchQueue(label: "slack-logger", qos: .utility)
    
    public init(webhookURL: URL, channel: String = "#logs") {
        self.webhookURL = webhookURL
        self.channel = channel
        self.session = URLSession.shared
    }
    
    public func log(_ entry: LogEntry) {
        guard isEnabled && entry.level >= minimumLevel else { return }
        
        if let filter = filter, !filter.shouldLog(entry) {
            return
        }
        
        queue.async { [weak self] in
            self?.sendToSlack(entry)
        }
    }
    
    public func configure(with config: EngineConfiguration) {
        self.minimumLevel = config.minimumLevel
        self.isEnabled = config.isEnabled
    }
    
    public func flush() async {
        // Wait for pending network requests
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume()
            }
        }
    }
    
    public func close() {
        session.invalidateAndCancel()
    }
    
    private func sendToSlack(_ entry: LogEntry) {
        let payload: [String: Any] = [
            "channel": channel,
            "username": "SwiftMoLogger",
            "icon_emoji": entry.level.emoji,
            "text": formatter.format(entry),
            "attachments": [[
                "color": entry.level == .critical ? "danger" : "warning",
                "fields": [
                    ["title": "Level", "value": entry.level.rawValue, "short": true],
                    ["title": "Tag", "value": entry.tag?.rawValue ?? "None", "short": true],
                    ["title": "File", "value": entry.metadata.fileName, "short": true],
                    ["title": "Line", "value": "\(entry.metadata.line)", "short": true]
                ]
            ]]
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload) else {
            return
        }
        
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        session.dataTask(with: request).resume()
    }
}

// Usage with builder
SwiftMoLogger.configure { builder in
    builder
        .minimumLevel(.debug)
        .addConsoleEngine()
        .addEngine(SlackLogEngine(
            webhookURL: URL(string: "https://hooks.slack.com/...")!,
            channel: "#critical-errors"
        ))
}
```

### Custom Engine with Storage and Rotation

```swift
/// Rolling file engine with compression
public class RollingFileLogEngine: LogEngine {
    public let id: String = "rolling-file"
    public let name: String = "Rolling File"
    public var isEnabled: Bool = true
    public var minimumLevel: LogLevel = .info
    public var formatter: LogFormatter = StandardLogFormatter()
    public var filter: LogFilter?
    
    private let baseURL: URL
    private let maxFileSize: Int
    private let maxFiles: Int
    private let compressionEnabled: Bool
    
    private var currentFileHandle: FileHandle?
    private let queue = DispatchQueue(label: "rolling-file-engine", qos: .utility)
    
    public init(
        baseURL: URL,
        maxFileSize: Int = 10 * 1024 * 1024, // 10MB
        maxFiles: Int = 10,
        compressionEnabled: Bool = true
    ) {
        self.baseURL = baseURL
        self.maxFileSize = maxFileSize
        self.maxFiles = maxFiles
        self.compressionEnabled = compressionEnabled
        
        setupCurrentFile()
    }
    
    public func log(_ entry: LogEntry) {
        guard isEnabled && entry.level >= minimumLevel else { return }
        
        if let filter = filter, !filter.shouldLog(entry) {
            return
        }
        
        queue.async { [weak self] in
            self?.writeToFile(entry)
        }
    }
    
    public func configure(with config: EngineConfiguration) {
        self.minimumLevel = config.minimumLevel
        self.isEnabled = config.isEnabled
    }
    
    public func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                self?.currentFileHandle?.synchronizeFile()
                continuation.resume()
            }
        }
    }
    
    public func close() {
        queue.sync {
            currentFileHandle?.closeFile()
            currentFileHandle = nil
        }
    }
    
    private func setupCurrentFile() {
        let currentLogURL = baseURL.appendingPathComponent("current.log")
        
        if !FileManager.default.fileExists(atPath: currentLogURL.path) {
            FileManager.default.createFile(atPath: currentLogURL.path, contents: nil)
        }
        
        currentFileHandle = try? FileHandle(forWritingTo: currentLogURL)
        currentFileHandle?.seekToEndOfFile()
    }
    
    private func writeToFile(_ entry: LogEntry) {
        guard let fileHandle = currentFileHandle else { return }
        
        // Check if rotation is needed
        if shouldRotateFile() {
            rotateFiles()
            setupCurrentFile()
        }
        
        let formattedMessage = formatter.format(entry) + "\n"
        if let data = formattedMessage.data(using: .utf8) {
            fileHandle.write(data)
        }
    }
    
    private func shouldRotateFile() -> Bool {
        let currentLogURL = baseURL.appendingPathComponent("current.log")
        
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: currentLogURL.path),
              let fileSize = attributes[.size] as? Int else {
            return false
        }
        
        return fileSize > maxFileSize
    }
    
    private func rotateFiles() {
        currentFileHandle?.closeFile()
        currentFileHandle = nil
        
        let fm = FileManager.default
        let currentLogURL = baseURL.appendingPathComponent("current.log")
        
        // Rotate existing files
        for i in stride(from: maxFiles - 1, to: 0, by: -1) {
            let oldURL = baseURL.appendingPathComponent("app-\(i).log")
            let newURL = baseURL.appendingPathComponent("app-\(i + 1).log")
            
            if fm.fileExists(atPath: oldURL.path) {
                try? fm.moveItem(at: oldURL, to: newURL)
            }
        }
        
        // Move current to app-1.log
        let rotatedURL = baseURL.appendingPathComponent("app-1.log")
        try? fm.moveItem(at: currentLogURL, to: rotatedURL)
        
        // Compress if enabled
        if compressionEnabled {
            Task {
                await compressFile(at: rotatedURL)
            }
        }
        
        // Remove excess files
        let excessURL = baseURL.appendingPathComponent("app-\(maxFiles + 1).log")
        if fm.fileExists(atPath: excessURL.path) {
            try? fm.removeItem(at: excessURL)
        }
    }
    
    private func compressFile(at url: URL) async {
        // Implement compression logic here
        // This could use Foundation's compression APIs
    }
}
```

## 🧩 Creating Custom Formatters

```swift
/// Formatter that outputs structured logs for log analysis tools
public struct AnalyticsLogFormatter: LogFormatter {
    private let includeStackTrace: Bool
    private let environment: String
    
    public init(includeStackTrace: Bool = false, environment: String = "production") {
        self.includeStackTrace = includeStackTrace
        self.environment = environment
    }
    
    public func format(_ entry: LogEntry) -> String {
        var logData: [String: Any] = [
            "timestamp": entry.timestamp.iso8601String,
            "level": entry.level.rawValue,
            "message": entry.message,
            "environment": environment,
            "source": [
                "file": entry.metadata.fileName,
                "function": entry.metadata.function,
                "line": entry.metadata.line
            ]
        ]
        
        if let tag = entry.tag {
            logData["category"] = tag.rawValue
        }
        
        if let userId = entry.context.userId {
            logData["user_id"] = userId
        }
        
        if let sessionId = entry.context.sessionId {
            logData["session_id"] = sessionId
        }
        
        if includeStackTrace {
            logData["stack_trace"] = Thread.callStackSymbols
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: logData),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return entry.message
        }
        
        return jsonString
    }
}
```

## 🔍 Creating Custom Filters

```swift
/// Filter that only allows logs from specific classes
public struct ClassNameFilter: LogFilter {
    private let allowedClasses: Set<String>
    
    public init(allowedClasses: [String]) {
        self.allowedClasses = Set(allowedClasses)
    }
    
    public func shouldLog(_ entry: LogEntry) -> Bool {
        let className = entry.metadata.fileName
            .replacingOccurrences(of: ".swift", with: "")
        
        return allowedClasses.contains(className)
    }
}

/// Filter that suppresses duplicate messages within a time window
public class DuplicateSuppressionFilter: LogFilter {
    private let timeWindow: TimeInterval
    private var messageHistory: [String: Date] = [:]
    private let queue = DispatchQueue(label: "duplicate-filter", attributes: .concurrent)
    
    public init(timeWindow: TimeInterval = 60.0) { // 1 minute
        self.timeWindow = timeWindow
    }
    
    public func shouldLog(_ entry: LogEntry) -> Bool {
        let messageKey = "\(entry.level.rawValue):\(entry.message)"
        let now = Date()
        
        return queue.sync {
            defer {
                // Clean old entries
                let cutoff = now.addingTimeInterval(-timeWindow)
                messageHistory = messageHistory.filter { $0.value > cutoff }
            }
            
            if let lastSeen = messageHistory[messageKey],
               now.timeIntervalSince(lastSeen) < timeWindow {
                return false // Suppress duplicate
            }
            
            messageHistory[messageKey] = now
            return true
        }
    }
}
```

## ⚙️ Creating Custom Middleware

```swift
/// Middleware that adds performance metrics
public struct PerformanceMiddleware: LogMiddleware {
    private let startTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    public init() {}
    
    public func process(_ entry: LogEntry) -> LogEntry {
        let currentTime = CFAbsoluteTimeGetCurrent()
        let uptime = currentTime - startTime
        let memoryUsage = getCurrentMemoryUsage()
        
        var customData = entry.metadata.customData
        customData["uptime_seconds"] = String(format: "%.3f", uptime)
        customData["memory_mb"] = String(format: "%.1f", memoryUsage / 1024 / 1024)
        
        let updatedMetadata = LogMetadata(
            file: entry.metadata.file,
            function: entry.metadata.function,
            line: entry.metadata.line,
            thread: entry.metadata.thread,
            customData: customData
        )
        
        return LogEntry(
            id: entry.id,
            level: entry.level,
            message: entry.message,
            tag: entry.tag,
            timestamp: entry.timestamp,
            metadata: updatedMetadata,
            context: entry.context
        )
    }
    
    private func getCurrentMemoryUsage() -> Double {
        let info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        return result == KERN_SUCCESS ? Double(info.resident_size) : 0.0
    }
}
```

## 🏗️ Complete Custom Solution Example

Here's a complete example of a custom logging solution for a financial app:

```swift
import SwiftMoLogger

// Custom engine for audit logs
class AuditLogEngine: LogEngine {
    let id = "audit"
    let name = "Audit"
    var isEnabled = true
    var minimumLevel: LogLevel = .info
    var formatter: LogFormatter = AnalyticsLogFormatter(environment: "production")
    var filter: LogFilter?
    
    private let auditService: AuditService
    
    init(auditService: AuditService) {
        self.auditService = auditService
    }
    
    func log(_ entry: LogEntry) {
        guard isEnabled && entry.level >= minimumLevel else { return }
        
        // Only log financial transaction related entries
        guard entry.tag == LogTag.Business.business ||
              entry.tag == LogTag.Security.security else { return }
        
        let auditEntry = AuditEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level,
            message: entry.message,
            userId: entry.context.userId,
            sessionId: entry.context.sessionId,
            metadata: entry.metadata
        )
        
        auditService.record(auditEntry)
    }
    
    func configure(with config: EngineConfiguration) {
        self.minimumLevel = config.minimumLevel
        self.isEnabled = config.isEnabled
    }
    
    func flush() async {
        await auditService.flush()
    }
    
    func close() {
        auditService.close()
    }
}

// Configuration for a financial app
class FinancialAppLogger {
    static func configure() {
        SwiftMoLogger.configure { builder in
            builder
                .minimumLevel(.info)
                .addConsoleEngine(
                    minimumLevel: .debug,
                    formatter: VerboseLogFormatter()
                )
                .addFileEngine(
                    fileURL: getLogsDirectory().appendingPathComponent("app.log"),
                    minimumLevel: .warning
                )
                .addEngine(AuditLogEngine(auditService: AuditService.shared))
                .addEngine(SlackLogEngine(
                    webhookURL: URL(string: "https://hooks.slack.com/...")!,
                    channel: "#financial-alerts"
                ))
                .addContextMiddleware()
                .addSanitizationMiddleware(
                    sensitivePatterns: [
                        "ssn", "credit_card", "bank_account", 
                        "pin", "cvv", "routing_number"
                    ]
                )
                .addMiddleware(PerformanceMiddleware())
        }
    }
    
    private static func getLogsDirectory() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory,
                                                    in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Logs")
    }
}

// Usage in financial operations
class PaymentProcessor: LogTagged {
    var logTag: LogTag { .business }
    
    func processPayment(_ payment: Payment) {
        logInfo("Starting payment processing for amount: \(payment.amount)")
        
        // Process payment...
        
        if payment.isSuccessful {
            logInfo("Payment processed successfully", file: #file, function: #function, line: #line)
        } else {
            logError("Payment failed: \(payment.errorMessage ?? "Unknown error")")
        }
    }
}
```

## 📖 Usage Examples

### Basic Usage (Backward Compatible)

```swift
// This still works exactly as before
SwiftMoLogger.info(message: "App started")
SwiftMoLogger.warn(message: "Low memory warning")
SwiftMoLogger.error(message: "Network request failed", tag: LogTag.Network.api)
```

### Advanced Configuration

```swift
// Configure for development
SwiftMoLogger.configure { builder in
    builder
        .forDevelopment() // Sets debug level and verbose console output
        .addFileEngine(fileURL: debugLogFile)
        .addContextMiddleware(userId: "dev-user")
}

// Configure for production
SwiftMoLogger.configure { builder in
    builder
        .forProduction() // Sets warning level and sanitization
        .addFileEngine(fileURL: productionLogFile)
        .addNetworkEngine(
            endpoint: URL(string: "https://api.yourservice.com/logs")!,
            apiKey: "your-api-key"
        )
}

// Custom configuration
SwiftMoLogger.configure { builder in
    builder
        .minimumLevel(.info)
        .addEngine(YourCustomEngine())
        .addFormatter(name: "custom", formatter: YourCustomFormatter())
        .addFilter(name: "business-only", filter: TagLogFilter(allowedTags: [.business]))
        .addMiddleware(YourCustomMiddleware())
}
```

### Environment-Specific Setup

```swift
// Automatic environment detection
let logger = Environment.current.createLogger()
SwiftMoLogger.setShared(logger)

// Or explicit environment setup
switch Environment.current {
case .development:
    SwiftMoLogger.configure { $0.forDevelopment() }
case .production:
    SwiftMoLogger.configure { $0.forProduction() }
case .testing:
    SwiftMoLogger.configure { $0.forTesting() }
}
```

## 🎯 Best Practices

1. **Engine IDs**: Use unique, descriptive IDs for your engines
2. **Thread Safety**: Always implement thread-safe operations in your engines
3. **Resource Management**: Properly implement `flush()` and `close()` methods
4. **Configuration**: Support dynamic configuration through `configure(with:)`
5. **Error Handling**: Handle failures gracefully without crashing the app
6. **Performance**: Use background queues for I/O operations
7. **Memory**: Be mindful of memory usage, especially in batch operations
8. **Testing**: Create memory engines for unit tests

## 🧪 Testing Custom Engines

```swift
import XCTest
@testable import SwiftMoLogger

class CustomEngineTests: XCTestCase {
    func testDatabaseEngine() async {
        // Arrange
        let mockDB = MockDatabaseService()
        let engine = DatabaseLogEngine(databaseService: mockDB)
        let entry = LogEntry(level: .info, message: "Test message")
        
        // Act
        engine.log(entry)
        await engine.flush()
        
        // Assert
        XCTAssertEqual(mockDB.storedEntries.count, 1)
        XCTAssertEqual(mockDB.storedEntries.first?.message, "Test message")
    }
    
    func testMemoryEngineIntegration() {
        // Use memory engine for testing
        let memoryEngine = MemoryLogEngine()
        
        SwiftMoLogger.configure { builder in
            builder.addEngine(memoryEngine)
        }
        
        // Log something
        SwiftMoLogger.info(message: "Integration test", tag: .testing)
        
        // Verify
        let logs = memoryEngine.getLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.message, "Integration test")
    }
}
```

---

**Created by Mohammed Elnaggar (@MoElnaggar14)**  
**SwiftMoLogger v2.0 - Now with full extensibility!**