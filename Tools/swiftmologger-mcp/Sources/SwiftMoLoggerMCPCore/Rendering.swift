import Foundation
import SwiftMoLogger

/// Compact one-line renderings, so search results cost few tokens.
public enum Rendering {
    private static let time: Date.FormatStyle = Date.FormatStyle()
        .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
        .secondFraction(.fractional(3))

    /// `#42 14:02:11.482 ERROR [Checkout] Payment failed {code=402} CheckoutViewModel.swift:88`
    public static func line(_ stored: StoredEntry, metadataLimit: Int = 200, showDevice: Bool = false) -> String {
        let entry = stored.entry
        var parts = ["#\(stored.seq)", entry.timestamp.formatted(time), entry.level.description]
        if let tag = entry.tag { parts.append(tag.rawValue) }
        parts.append(entry.message)
        let metadata = metadataSummary(entry.metadata, limit: metadataLimit)
        if !metadata.isEmpty { parts.append("{\(metadata)}") }
        parts.append("\(fileName(entry.source.file)):\(entry.source.line)")
        if showDevice { parts.append("(\(stored.device))") }
        return parts.joined(separator: " ")
    }

    public static func metadataSummary(_ metadata: LogMetadata, limit: Int = 200) -> String {
        let text = metadata.storage
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.description)" }
            .joined(separator: ", ")
        guard text.count > limit else { return text }
        return String(text.prefix(limit)) + "…"
    }

    public static func metadataStrings(_ metadata: LogMetadata) -> [String: String] {
        metadata.storage.mapValues(\.description)
    }

    static func fileName(_ fileID: String) -> String {
        fileID.split(separator: "/").last.map(String.init) ?? fileID
    }
}
