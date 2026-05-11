import Foundation
import os.log

/// Apple unified-logging backend. Routes every entry through `os.Logger`
/// (iOS 14+) so messages show up in Console.app, Instruments, and `log
/// stream`. Falls back to `print` on older OS versions and exclusively in
/// debug builds.
///
/// Bug fix vs. v2: info/warn entries were previously dropped on release
/// builds because the entire body was wrapped in `#if DEBUG`. They are now
/// always forwarded to `os.log`; only the `print` fallback remains
/// debug-only.
public final class SystemLogger: LogEngine, @unchecked Sendable {
    public let engineID: String
    public let minimumLevel: LogLevel

    private let osLog: OSLog
    private let usePrintFallback: Bool

    public init(
        subsystem: String? = nil,
        category: String = "General",
        minimumLevel: LogLevel = .trace,
        usePrintFallback: Bool = false
    ) {
        let resolvedSubsystem = subsystem ?? Bundle.main.bundleIdentifier ?? "SwiftMoLogger"
        self.osLog = OSLog(subsystem: resolvedSubsystem, category: category)
        self.engineID = "swiftmologger.system.\(resolvedSubsystem).\(category)"
        self.minimumLevel = minimumLevel
        self.usePrintFallback = usePrintFallback
    }

    public func log(_ entry: LogEntry) {
        let rendered = entry.formatted()
        os_log(entry.level.osLogType, log: osLog, "%{public}@", rendered)
        if usePrintFallback {
            print(rendered)
        }
    }
}
