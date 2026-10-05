import Foundation
import SwiftMoLogger
@testable import SwiftMoLoggerMCPCore

/// Encodes entries exactly as LiveSink does.
enum Wire {
    static func line(_ entry: LogEntry) -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        return try! encoder.encode(entry) // swiftlint:disable:this force_try
    }

    static func hello(app: String = "com.acme.shop", version: Int = 2) -> Data {
        let object: [String: Any] = [
            "kind": "hello", "service": "SwiftMoLogger.LiveSink", "version": version,
            "app": app, "app_version": "1.4.2", "os": "Version 27.0", "connected_at": "2026-10-05T14:00:00Z"
        ]
        return try! JSONSerialization.data(withJSONObject: object) // swiftlint:disable:this force_try
    }

    static func entry(
        _ message: String,
        level: LogLevel = .info,
        tag: LogTag? = nil,
        metadata: LogMetadata = [:],
        at timestamp: Date = Date()
    ) -> LogEntry {
        LogEntry(timestamp: timestamp, level: level, message: message, tag: tag, metadata: metadata,
                 source: SourceLocation(file: "Shop/CheckoutViewModel.swift", function: "pay()", line: 88, column: 1),
                 threadName: "main")
    }
}

extension DeviceHub {
    /// A connected device that has sent its hello and `entries`.
    func connect(_ device: String = "com.acme.shop", sending entries: [LogEntry] = []) {
        handle(.discovered(device: device))
        handle(.connected(device: device))
        handle(.line(device: device, data: Wire.hello(app: device)))
        for entry in entries { handle(.line(device: device, data: Wire.line(entry))) }
    }

    func send(_ entry: LogEntry, from device: String = "com.acme.shop") {
        handle(.line(device: device, data: Wire.line(entry)))
    }
}
