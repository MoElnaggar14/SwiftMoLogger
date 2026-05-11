import Foundation
import os.log

/// Severity level of a log entry, ordered from least to most severe.
///
/// Compatible with Apple's unified logging (`OSLogType`) and syslog severities,
/// so adopters can interoperate with `os.Logger`, structured log backends, and
/// crash reporters without translation layers.
public enum LogLevel: Int, Sendable, Hashable, CaseIterable, Codable, Comparable, CustomStringConvertible {
    case trace = 0
    case debug = 1
    case info = 2
    case notice = 3
    case warning = 4
    case error = 5
    case critical = 6
    case fault = 7

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        case .fault: return "FAULT"
        }
    }

    /// Single-character glyph for compact rendering (`[I]`, `[E]`, …).
    public var glyph: String {
        switch self {
        case .trace: return "T"
        case .debug: return "D"
        case .info: return "I"
        case .notice: return "N"
        case .warning: return "W"
        case .error: return "E"
        case .critical: return "C"
        case .fault: return "F"
        }
    }

    /// Emoji marker used by console-style renderers.
    public var emoji: String {
        switch self {
        case .trace: return "🔬"
        case .debug: return "🐛"
        case .info: return "ℹ️"
        case .notice: return "📌"
        case .warning: return "⚠️"
        case .error: return "🚨"
        case .critical: return "💥"
        case .fault: return "☠️"
        }
    }

    /// Mapping to Apple's unified logging type so engines can forward without
    /// reinterpreting severity.
    public var osLogType: OSLogType {
        switch self {
        case .trace, .debug: return .debug
        case .info: return .info
        case .notice: return .default
        case .warning: return .default
        case .error: return .error
        case .critical, .fault: return .fault
        }
    }
}
