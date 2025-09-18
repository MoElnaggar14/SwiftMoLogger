import Foundation
import os.log

// MARK: - System Logger

/// High-performance system logger using os.log (iOS 14+) with console fallback
public final class SystemLogger: LogEngine {
    private let osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "SwiftMoLogger", category: "General")

    public init() {}

    public func info(message: String) {
        #if DEBUG
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            os_log(.info, log: osLog, "%{public}@", "ℹ️ \(message)")
        } else {
            print("ℹ️ \(message)")
        }
        #endif
    }

    public func warn(message: String) {
        #if DEBUG
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            os_log(.default, log: osLog, "%{public}@", "⚠️ \(message)")
        } else {
            print("⚠️ \(message)")
        }
        #endif
    }

    public func error(message: String) {
        if #available(iOS 14.0, macOS 11.0, tvOS 14.0, watchOS 7.0, *) {
            os_log(.error, log: osLog, "%{public}@", "🚨 \(message)")
        } else {
            print("🚨 \(message)")
        }
    }
}
