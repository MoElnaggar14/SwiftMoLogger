import Foundation

/// SwiftLogger - A comprehensive logging framework for iOS applications
/// 
/// SwiftLogger provides a scalable, tagged logging system with MetricKit crash reporting integration.
/// Designed for modern iOS development with support for structured logging and automatic context management.
///
/// ## Quick Start
/// ```swift
/// import SwiftLogger
/// 
/// // Basic logging
/// SwiftLogger.info(message: "App started")
/// SwiftLogger.warn(message: "Low memory warning")
/// SwiftLogger.error(message: "Failed to load data")
/// 
/// // Tagged logging
/// SwiftLogger.info(message: "API request started", tag: LogTag.Network.api)
/// SwiftLogger.error(message: "Database error", tag: LogTag.Data.database)
/// ```
///
/// ## Features
/// - Multi-level logging (Info, Warning, Error)
/// - Comprehensive tag system organized by domain
/// - MetricKit crash reporting integration
/// - Protocol-based automatic context logging
/// - Extensible architecture with pluggable engines
/// - iOS 15+ with modern async/await support
public enum SwiftLogger {
    private static var engines: [LogEngine] {
        .all
    }

    /// Logs an informational message
    /// - Parameter message: The message to log
    public static func info(message: String) {
        engines.forEach { $0.info(message: message) }
    }

    /// Logs a warning message
    /// - Parameter message: The message to log
    public static func warn(message: String) {
        engines.forEach { $0.warn(message: message) }
    }

    /// Logs an error message
    /// - Parameter message: The message to log
    public static func error(message: String) {
        engines.forEach { $0.error(message: message) }
    }
    
    /// Logs an informational message with the specified tag
    /// - Parameters:
    ///   - message: The message to log
    ///   - tag: The tag to apply to the message
    public static func info(message: String, tag: LogTag) {
        info(message: message.tagWith(tag))
    }
    
    /// Logs a warning message with the specified tag
    /// - Parameters:
    ///   - message: The message to log
    ///   - tag: The tag to apply to the message
    public static func warn(message: String, tag: LogTag) {
        warn(message: message.tagWith(tag))
    }
    
    /// Logs an error message with the specified tag
    /// - Parameters:
    ///   - message: The message to log
    ///   - tag: The tag to apply to the message
    public static func error(message: String, tag: LogTag) {
        error(message: message.tagWith(tag))
    }
    
    /// Logs a debug message (only in DEBUG builds) with the specified tag
    /// - Parameters:
    ///   - message: The message to log
    ///   - tag: The tag to apply to the message
    public static func debug(message: String, tag: LogTag = .debug) {
        #if DEBUG
        info(message: message.tagWith(tag))
        #endif
    }
    
    /// Logs a crash-related message with error level
    /// - Parameter message: The crash-related message to log
    public static func crash(message: String) {
        error(message: message.tagWith(.crash))
    }
}

// MARK: - String Extensions
extension String {
    func tagWith(_ tag: LogTag) -> String {
        withPrefix("\(tag.rawValue) ")
    }

    func tagWith(_ tags: [LogTag]) -> String {
        tags.map { "[\($0.rawValue)]" }.joined().withPrefix(" \(self)")
    }

    func withPrefix(_ prefix: String) -> String {
        "\(prefix)\(self)"
    }
}