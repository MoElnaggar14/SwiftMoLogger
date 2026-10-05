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
    /// How messages appear in the unified log when no debugger is attached.
    ///
    /// The unified log ends up in sysdiagnose archives that users share with
    /// support, so anything `public` there should be safe to leak.
    public enum Privacy: Sendable {
        /// Always readable. The historical default.
        case `public`
        /// Shown as `<private>` unless a debugger is attached or a logging
        /// profile is installed.
        case `private`
        /// Like `private`, but replaced by a stable hash so identical
        /// messages can still be correlated.
        case hashed
        /// `public` in DEBUG builds, `private` otherwise. Apple's recommended
        /// setting for apps.
        case privateInRelease

        var resolved: Privacy {
            guard self == .privateInRelease else { return self }
            #if DEBUG
            return .public
            #else
            return .private
            #endif
        }
    }

    public let engineID: String
    public let minimumLevel: LogLevel
    public let privacy: Privacy

    private let osLog: OSLog
    private let usePrintFallback: Bool

    public init(
        subsystem: String? = nil,
        category: String = "General",
        minimumLevel: LogLevel = .trace,
        privacy: Privacy = .public,
        usePrintFallback: Bool = false
    ) {
        let resolvedSubsystem = subsystem ?? Bundle.main.bundleIdentifier ?? "SwiftMoLogger"
        self.osLog = OSLog(subsystem: resolvedSubsystem, category: category)
        self.engineID = "swiftmologger.system.\(resolvedSubsystem).\(category)"
        self.minimumLevel = minimumLevel
        self.privacy = privacy.resolved
        self.usePrintFallback = usePrintFallback
    }

    public func log(_ entry: LogEntry) {
        let rendered = entry.formatted()
        let type = entry.level.osLogType
        // os_log needs a StaticString format, so each privacy level is spelled out.
        switch privacy {
        case .public, .privateInRelease:
            os_log(type, log: osLog, "%{public}@", rendered)
        case .private:
            os_log(type, log: osLog, "%{private}@", rendered)
        case .hashed:
            os_log(type, log: osLog, "%{private, mask.hash}@", rendered)
        }
        if usePrintFallback {
            print(rendered)
        }
    }
}
