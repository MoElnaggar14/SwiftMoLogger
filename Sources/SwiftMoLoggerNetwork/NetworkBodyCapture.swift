import Foundation
import SwiftMoLogger

/// Whether a ``NetworkLogger`` captures request and response bodies for the
/// Diagnostics Hub.
///
/// Bodies are the most sensitive part of an exchange, so capture is off by
/// default. Captured bodies go through the logger's `Redactor`, are cut at
/// `maxBytes`, and are kept only for text content types (JSON, XML, `text/*`,
/// form-encoded, JavaScript, GraphQL, YAML). Images, video, protobuf,
/// multipart uploads and other binary bodies are skipped. Bodies are stored in
/// the ``NetworkEvent`` only; they're never written to log entries.
public enum NetworkBodyCapture: Sendable, Hashable {
    /// Captures nothing. The default.
    case off
    /// Captures up to `maxBytes` of each body in debug builds (`DEBUG` is
    /// defined) and nothing in release builds.
    case debugOnly(maxBytes: Int)
    /// Captures up to `maxBytes` of each body in every build, release included.
    /// Opt in only when you've decided bodies may live in memory (and in the
    /// flight recorder, if you use one) on users' devices.
    case always(maxBytes: Int)

    /// A sensible limit: 64 KB per body.
    public static let defaultMaxBytes = 64 * 1_024

    /// The byte limit in effect for this build, or `nil` when nothing is captured.
    var effectiveLimit: Int? {
        switch self {
        case .off:
            return nil
        case .debugOnly(let maxBytes):
            #if DEBUG
            return maxBytes > 0 ? maxBytes : nil
            #else
            return nil
            #endif
        case .always(let maxBytes):
            return maxBytes > 0 ? maxBytes : nil
        }
    }
}

/// Turns raw body bytes into a redacted, truncated ``NetworkBody``.
struct NetworkBodyEncoder: Sendable {
    let maxBytes: Int
    let redactor: Redactor

    /// Extra bytes buffered past the limit, so a secret that straddles the
    /// limit is still whole when the redactor sees it.
    static let redactionSlack = 1_024

    /// How many bytes to buffer before giving up on the rest.
    var bufferLimit: Int {
        maxBytes > Int.max - Self.redactionSlack ? Int.max : maxBytes + Self.redactionSlack
    }

    /// `nil` when the body is empty or not text.
    func body(from data: Data, totalBytes: Int, contentType: String?) -> NetworkBody? {
        guard !data.isEmpty, Self.isTextual(contentType, sample: data),
              let decoded = Self.decodeUTF8(data.prefix(bufferLimit)) else { return nil }
        let redacted = redactor.redact(decoded).output
        let (text, cut) = Self.prefix(redacted, maxUTF8Bytes: maxBytes)
        return NetworkBody(text: text, contentType: contentType, isTruncated: cut || totalBytes > bufferLimit)
    }

    // MARK: - Content types

    /// Subtype fragments that mark a non-`text/*` type as text.
    static let textualFragments = [
        "json", "xml", "x-www-form-urlencoded", "javascript", "ecmascript", "graphql", "yaml", "csv"
    ]

    /// `true` for text-like types, `false` for anything else. With no content
    /// type, `sample` decides: text if it's valid UTF-8 with no NUL bytes.
    static func isTextual(_ contentType: String?, sample: Data) -> Bool {
        guard let contentType else {
            let head = sample.prefix(512)
            return !head.contains(0) && decodeUTF8(head) != nil
        }
        let mime = (contentType.split(separator: ";").first.map(String.init) ?? contentType)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if mime.hasPrefix("text/") { return true }
        return textualFragments.contains { mime.contains($0) }
    }

    // MARK: - UTF-8

    /// Decodes UTF-8, allowing the bytes to end mid-character (they were cut at
    /// a byte limit). `nil` if the bytes aren't UTF-8.
    static func decodeUTF8(_ data: Data) -> String? {
        for drop in 0...min(3, data.count) {
            if let string = String(data: data.dropLast(drop), encoding: .utf8) { return string }
        }
        return nil
    }

    /// The longest prefix of `string` that fits in `maxUTF8Bytes`, never
    /// splitting a character, and whether anything was cut.
    static func prefix(_ string: String, maxUTF8Bytes: Int) -> (String, Bool) {
        guard string.utf8.count > maxUTF8Bytes else { return (string, false) }
        var bytes = 0
        var end = string.startIndex
        for index in string.indices {
            let next = string.index(after: index)
            let width = string.utf8.distance(from: index, to: next)
            guard bytes + width <= maxUTF8Bytes else { break }
            bytes += width
            end = next
        }
        return (String(string[..<end]), true)
    }
}

/// Accumulates one task's response bytes, up to a limit.
struct ResponseBodyBuffer {
    var data = Data()
    var totalBytes = 0
    /// Set once the response turns out to be binary; nothing more is kept.
    var skipped = false
}
