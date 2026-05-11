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
///
/// The directory URL is returned so the caller can hand it directly to
/// `UIActivityViewController` / `ShareLink` / a custom uploader.
public struct BugReporter: Sendable {
    public struct Report: Sendable {
        public let directory: URL
        public let info: String
    }

    public let memoryEngine: MemoryLogEngine?
    public let appName: String

    public init(memoryEngine: MemoryLogEngine? = nil, appName: String = "App") {
        self.memoryEngine = memoryEngine
        self.appName = appName
    }

    public func generate(extras: LogMetadata = [:]) throws -> Report {
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BugReports", isDirectory: true)
            .appendingPathComponent("\(appName)-\(timestamp)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let info = deviceInfo()
        try info.write(to: root.appendingPathComponent("info.txt"), atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let breadcrumbs = SwiftMoLogger.breadcrumbs()
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

        if let sample = AppVitalsMonitor.shared.lastSample {
            try encoder.encode(sample)
                .write(to: root.appendingPathComponent("vitals.json"))
        }

        return Report(directory: root, info: info)
    }

    private func deviceInfo() -> String {
        var lines: [String] = []
        lines.append("Generated: \(Date())")
        let bundle = Bundle.main.infoDictionary
        lines.append("App: \(bundle?["CFBundleName"] as? String ?? "?")")
        lines.append("Version: \(bundle?["CFBundleShortVersionString"] as? String ?? "?") (\(bundle?["CFBundleVersion"] as? String ?? "?"))")
        #if canImport(UIKit)
        let device = UIDevice.current
        lines.append("Device: \(device.model)")
        lines.append("OS: \(device.systemName) \(device.systemVersion)")
        #endif
        lines.append("Locale: \(Locale.current.identifier)")
        if let info = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let free = info[.systemFreeSize] as? Int64 {
            lines.append("Free disk: \(ByteCountFormatter.string(fromByteCount: free, countStyle: .file))")
        }
        lines.append("Breadcrumbs: \(SwiftMoLogger.breadcrumbs().count)")
        lines.append("Engines: \(SwiftMoLogger.allEngines().map(\.engineID).joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }
}
