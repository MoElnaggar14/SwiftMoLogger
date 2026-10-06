import Foundation
import SwiftMoLogger
// Test attachments are public from Swift 6.2 (ST-0009); 6.1 only has them as SPI.
#if canImport(Testing) && compiler(>=6.2)
import Testing
#endif

extension RecordingLogEngine {
    /// The recorded entries as plain text, one line per entry:
    /// `2026-10-06T12:00:00.123Z ERROR [API] Payment declined {order_id=42} (Shop/Checkout.swift:12)`.
    func attachmentText() -> String {
        let time = ISO8601DateFormatter()
        time.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return recorded().map { entry in
            var line = "\(time.string(from: entry.timestamp)) \(entry.level.description)"
            if let tag = entry.tag { line += " \(tag.rawValue)" }
            line += " \(entry.message)"
            if !entry.metadata.isEmpty {
                let pairs = entry.metadata.storage
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value.description)" }
                    .joined(separator: " ")
                line += " {\(pairs)}"
            }
            line += " (\(entry.source.file):\(entry.source.line))"
            return line
        }.joined(separator: "\n")
    }
}

#if canImport(Testing) && compiler(>=6.2)
public extension RecordingLogEngine {
    /// Attaches the recorded entries to the current Swift Testing test as a text file,
    /// one line per entry. Xcode shows it in the test report; `swift test` saves it
    /// when you pass `--attachments-path`.
    ///
    /// Attach in a `defer`, so the logs are there when an expectation fails:
    ///
    /// ```swift
    /// @Test func declinedPaymentIsLogged() async throws {
    ///     let (log, logs) = MoLogger.recording()
    ///     defer { logs.attach() }
    ///     try await CheckoutService(log: log).purchase(invalid: true)
    ///     #expect(logs.contains(.error, containing: "declined"))
    /// }
    /// ```
    ///
    /// - Parameter name: The file name, without an extension; `.txt` is added.
    func attach(named name: String = "logs", sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        let bytes = Array(attachmentText().utf8)
        Attachment.record(bytes, named: "\(name).txt", sourceLocation: sourceLocation)
    }
}
#endif
