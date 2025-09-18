import Foundation

/// SwiftMoLogger - Modern, extensible logging framework for iOS applications
///
/// ## Features
/// - Clean, thread-safe architecture
/// - Extensible with custom engines
/// - Comprehensive tagging system
/// - High-performance os.log integration
/// - MetricKit crash reporting
///
/// ## Usage
/// ```swift
/// // Basic logging
/// SwiftMoLogger.info("App started")
/// SwiftMoLogger.warn("Low memory")
/// SwiftMoLogger.error("Network failed")
///
/// // Tagged logging
/// SwiftMoLogger.info("API success", tag: .api)
/// SwiftMoLogger.error("DB error", tag: .database)
///
/// // Custom engines
/// SwiftMoLogger.addEngine(FileLogEngine())
/// ```
///
/// Created by Mohammed Elnaggar (@MoElnaggar14)
public enum SwiftMoLogger {
    // MARK: - Core Logging

    /// Log informational message
    public static func info(_ message: String) {
        EngineRegistry.shared.getAllEngines().forEach { $0.info(message: message) }
    }

    /// Log warning message
    public static func warn(_ message: String) {
        EngineRegistry.shared.getAllEngines().forEach { $0.warn(message: message) }
    }

    /// Log error message
    public static func error(_ message: String) {
        EngineRegistry.shared.getAllEngines().forEach { $0.error(message: message) }
    }

    // MARK: - Tagged Logging

    /// Log informational message with tag
    public static func info(_ message: String, tag: LogTag) {
        info("\(tag.rawValue) \(message)")
    }

    /// Log warning message with tag
    public static func warn(_ message: String, tag: LogTag) {
        warn("\(tag.rawValue) \(message)")
    }

    /// Log error message with tag
    public static func error(_ message: String, tag: LogTag) {
        error("\(tag.rawValue) \(message)")
    }

    /// Log debug message (DEBUG builds only)
    public static func debug(_ message: String, tag: LogTag = .debug) {
        #if DEBUG
        info("\(tag.rawValue) \(message)")
        #endif
    }

    /// Log crash-related message
    public static func crash(_ message: String) {
        error("\(LogTag.crash.rawValue) \(message)")
    }

    // MARK: - Engine Management

    /// Add custom logging engine
    public static func addEngine(_ engine: LogEngine) {
        EngineRegistry.shared.addEngine(engine)
    }

    /// Remove engine at index (system logger at index 0 cannot be removed)
    public static func removeEngine(at index: Int) {
        EngineRegistry.shared.removeEngine(at: index)
    }

    /// Get all registered engines
    public static func getAllEngines() -> [LogEngine] {
        EngineRegistry.shared.getAllEngines()
    }

    /// Count of all engines
    public static var engineCount: Int {
        EngineRegistry.shared.engineCount
    }

    /// Reset to system logger only
    public static func reset() {
        EngineRegistry.shared.reset()
    }
}

// MARK: - Convenience Protocol

/// Protocol for objects with automatic logging context
public protocol LogTagged {
    var logTag: LogTag { get }
}

/// Automatic logging methods for LogTagged objects
public extension LogTagged {
    func logInfo(_ message: String) {
        SwiftMoLogger.info(message, tag: logTag)
    }

    func logWarn(_ message: String) {
        SwiftMoLogger.warn(message, tag: logTag)
    }

    func logError(_ message: String) {
        SwiftMoLogger.error(message, tag: logTag)
    }

    func logDebug(_ message: String) {
        SwiftMoLogger.debug(message, tag: logTag)
    }
}
