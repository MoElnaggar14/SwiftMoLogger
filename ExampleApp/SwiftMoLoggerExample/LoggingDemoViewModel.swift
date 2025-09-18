import SwiftUI
import SwiftMoLogger
import Combine

class LoggingDemoViewModel: ObservableObject {
    @Published var engineCount: Int = 0
    @Published var totalLogs: Int = 0
    @Published var errorCount: Int = 0
    @Published var warningCount: Int = 0
    @Published var memoryLogCount: Int = 0
    @Published var fileSize: String = "0 bytes"
    @Published var recentLogs: [MemoryLogEngine.LogEntry] = []
    
    private var memoryEngine: MemoryLogEngine?
    private var fileEngine: FileLogEngine?
    private var analyticsEngine: AnalyticsLogEngine?
    private var updateTimer: Timer?
    
    init() {
        findEngines()
        updateStats()
    }
    
    // MARK: - Public Methods
    
    func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                self.updateStats()
            }
        }
    }
    
    func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    func logInfo() {
        let messages = [
            "📱 User tapped info button",
            "✅ Operation completed successfully",
            "📊 Data loaded from cache",
            "🎯 Feature accessed by user",
            "📝 Configuration updated",
            "🔄 Sync operation initiated",
            "💾 Data saved to local storage"
        ]
        
        let message = messages.randomElement() ?? "Info log generated"
        SwiftMoLogger.info(message, tag: .ui)
    }
    
    func logWarning() {
        let warnings = [
            "⚠️ Low storage space detected",
            "🔋 Battery level is low",
            "📶 Weak network connection",
            "⏰ Operation took longer than expected",
            "🎯 Feature deprecated - please update",
            "📱 Device orientation changed unexpectedly",
            "🔄 Retry attempt initiated"
        ]
        
        let message = warnings.randomElement() ?? "Warning generated"
        SwiftMoLogger.warn(message, tag: .ui)
    }
    
    func logError() {
        let errors = [
            "❌ Failed to load user data",
            "🔐 Authentication failed",
            "📡 Network request timed out",
            "💾 Failed to save to disk",
            "🎯 Invalid API response format",
            "⚡ Unexpected application state",
            "🔄 Maximum retry attempts exceeded"
        ]
        
        let message = errors.randomElement() ?? "Error occurred"
        SwiftMoLogger.error(message, tag: .api)
    }
    
    func simulateNetworkOperation() {
        SwiftMoLogger.info("🌐 Starting network request...", tag: .network)
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.5) {
            let success = Bool.random()
            
            if success {
                SwiftMoLogger.info("✅ Network request completed successfully", tag: .network)
                SwiftMoLogger.info("📈 Response time: 247ms", tag: .performance)
            } else {
                SwiftMoLogger.error("❌ Network request failed - timeout", tag: .network)
                SwiftMoLogger.warn("🔄 Will retry in 5 seconds", tag: .network)
            }
        }
    }
    
    func simulatePerformanceIssue() {
        SwiftMoLogger.info("🔍 Running performance test...", tag: .performance)
        
        let operations = [
            ("Database query", 150),
            ("Image processing", 300),
            ("Data parsing", 85),
            ("UI rendering", 200),
            ("File encryption", 500)
        ]
        
        let (operation, duration) = operations.randomElement() ?? ("Operation", 100)
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            if duration > 200 {
                SwiftMoLogger.warn("⏱️ \(operation) took \(duration)ms (slow performance detected)", tag: .performance)
            } else {
                SwiftMoLogger.info("✅ \(operation) completed in \(duration)ms", tag: .performance)
            }
        }
    }
    
    func simulateBackgroundTask() {
        SwiftMoLogger.info("🔄 Background task started", tag: .lifecycle)
        
        let tasks = [
            "Data synchronization",
            "Cache cleanup", 
            "Log file rotation",
            "Analytics upload",
            "Background app refresh"
        ]
        
        let task = tasks.randomElement() ?? "Background task"
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) {
            SwiftMoLogger.info("✅ \(task) completed successfully", tag: .lifecycle)
        }
    }
    
    func clearMemoryLogs() {
        memoryEngine?.clear()
        updateStats()
    }
    
    func resetAnalytics() {
        analyticsEngine?.reset()
        updateStats()
    }
    
    func getLogFileURL() -> URL? {
        return fileEngine?.getLogFileURL()
    }
    
    // MARK: - Private Methods
    
    private func findEngines() {
        let engines = SwiftMoLogger.getAllEngines()
        
        for engine in engines {
            if let memEngine = engine as? MemoryLogEngine {
                self.memoryEngine = memEngine
            } else if let fileEng = engine as? FileLogEngine {
                self.fileEngine = fileEng
            } else if let analyticsEng = engine as? AnalyticsLogEngine {
                self.analyticsEngine = analyticsEng
            }
        }
    }
    
    @MainActor
    private func updateStats() {
        engineCount = SwiftMoLogger.engineCount
        
        if let memEngine = memoryEngine {
            let logs = memEngine.getAllLogs()
            memoryLogCount = logs.count
            recentLogs = memEngine.getRecentLogs(count: 10)
            errorCount = memEngine.getErrorCount()
            
            // Count warnings from memory logs
            warningCount = logs.filter { $0.level == "WARN" }.count
            totalLogs = logs.count
        }
        
        if let fileEng = fileEngine {
            fileSize = fileEng.getLogFileSize()
        }
        
        if let analytics = analyticsEngine {
            let metrics = analytics.getMetrics()
            // Analytics engine provides its own counts which might be different
            // from memory engine if they started at different times
        }
    }
}

// MARK: - Example Network Service with LogTagged

struct NetworkService: LogTagged {
    var logTag: LogTag { .network }
    
    func fetchUserData() {
        logInfo("🌐 Fetching user data from API")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if Bool.random() {
                self.logInfo("✅ User data loaded successfully")
            } else {
                self.logError("❌ Failed to fetch user data - server error")
            }
        }
    }
    
    func uploadAnalytics() {
        logInfo("📊 Uploading analytics data")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
            self.logInfo("✅ Analytics uploaded successfully")
        }
    }
}

// MARK: - Example Database Service with LogTagged

struct DatabaseService: LogTagged {
    var logTag: LogTag { .database }
    
    func saveUserSettings() {
        logInfo("💾 Saving user settings to database")
        
        if Bool.random() {
            logInfo("✅ Settings saved successfully")
        } else {
            logError("❌ Failed to save settings - disk full")
        }
    }
    
    func performMaintenance() {
        logInfo("🔧 Starting database maintenance")
        logWarn("⚠️ This operation may take several minutes")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
            self.logInfo("✅ Database maintenance completed")
        }
    }
}