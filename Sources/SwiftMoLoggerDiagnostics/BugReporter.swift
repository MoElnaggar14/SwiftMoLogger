import Foundation
import SwiftMoLogger

#if canImport(UIKit)
import UIKit
#endif

/// One-call snapshot bundle suitable for "Send Bug Report" buttons.
///
/// The output is a directory inside the user's caches folder containing:
/// - `info.txt`           — device, OS, app version, locale, free disk
/// - `breadcrumbs.json`   — recent breadcrumbs
/// - `logs.json`          — entries captured by the supplied
///                          ``MemoryLogEngine``
/// - `vitals.json`        — last vitals sample (if a monitor is attached)
/// - `metadata.json`      — caller-supplied extras
/// - `system-log.txt`     — recent unified-log entries from Apple frameworks and SDKs,
///                          redacted, when you pass ``SystemLogOptions``
///
/// The directory URL is returned so the caller can hand it directly to
/// `UIActivityViewController` / `ShareLink` / a custom uploader.
public struct BugReporter: Sendable {
    public struct Report: Sendable {
        public let directory: URL
        public let info: String
    }

    public let environment: LogEnvironment
    public let memoryEngine: MemoryLogEngine?
    public let vitalsMonitor: AppVitalsMonitor?
    public let appName: String
    public let systemLog: SystemLogOptions?

    /// - Parameters:
    ///   - environment: Supplies breadcrumbs and the list of active engines.
    ///   - memoryEngine: Recent entries to include as `logs.json`.
    ///   - vitalsMonitor: Its last sample is included as `vitals.json`.
    ///   - systemLog: Adds the last ``SystemLogOptions/window`` seconds of this process's
    ///     unified log as `system-log.txt`. Off by default; reading it takes a moment.
    public init(
        environment: LogEnvironment,
        memoryEngine: MemoryLogEngine? = nil,
        vitalsMonitor: AppVitalsMonitor? = nil,
        appName: String = "App",
        systemLog: SystemLogOptions? = nil
    ) {
        self.environment = environment
        self.memoryEngine = memoryEngine
        self.vitalsMonitor = vitalsMonitor
        self.appName = appName
        self.systemLog = systemLog
    }

    public func generate(extras: LogMetadata = [:]) throws -> Report {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BugReports", isDirectory: true)
            // The suffix keeps two reports generated in the same second apart.
            .appendingPathComponent("\(appName)-\(timestamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let info = deviceInfo()
        try info.write(to: root.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let breadcrumbs = environment.breadcrumbs.snapshot()
        try encoder.encode(breadcrumbs)
            .write(to: root.appendingPathComponent("breadcrumbs.json"))

        if let memory = memoryEngine {
            try encoder.encode(memory.snapshot())
                .write(to: root.appendingPathComponent("logs.json"))
        }

        if !extras.isEmpty {
            try encoder.encode(extras)
                .write(to: root.appendingPathComponent("metadata.json"))
        }

        if let sample = vitalsMonitor?.lastSample {
            try encoder.encode(sample)
                .write(to: root.appendingPathComponent("vitals.json"))
        }

        if let systemLog {
            let text: String
            do {
                let since = Date().addingTimeInterval(-systemLog.window)
                text = systemLog.render(try systemLog.source.entries(since: since))
            } catch {
                // The rest of the report is still worth sending.
                text = "System log unavailable: \(error.localizedDescription)"
            }
            try text.write(to: root.appendingPathComponent("system-log.txt"), atomically: true, encoding: .utf8)
        }

        return Report(directory: root, info: info)
    }

    private func deviceInfo() -> String {
        var lines: [String] = []
        lines.append("Generated: \(Date())")
        let bundle = Bundle.main.infoDictionary
        lines.append("App: \(bundle?["CFBundleName"] as? String ?? "?")")
        let shortVersion = bundle?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle?["CFBundleVersion"] as? String ?? "?"
        lines.append("Version: \(shortVersion) (\(build))")
        lines.append("Device: \(Self.hardwareModel())")
        lines.append("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Locale: \(Locale.current.identifier)")
        if let info = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = info[.systemFreeSize] as? Int64 {
            lines.append("Free disk: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))")
        }
        lines.append("Breadcrumbs: \(environment.breadcrumbs.snapshot().count)")
        lines.append("Engines: \(environment.registry.allEngines().map(\.engineID).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }

    /// The hardware model identifier (e.g. `iPhone16,2`). Read with `sysctl`
    /// rather than `UIDevice`, which is main-actor isolated and missing on watchOS.
    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var machine = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else { return "unknown" }
        return String(decoding: machine.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
