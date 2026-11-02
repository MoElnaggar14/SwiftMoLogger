import Foundation

/// How an interpolated value appears in a ``LogMessage``.
///
/// Mirrors the names of `os.Logger`'s privacy options:
///
/// ```swift
/// log.info("Signed in \(email, privacy: .private)")         // "Signed in <private>"
/// log.info("Opened \(screen, privacy: .public)")            // "Opened Settings"
/// log.info("Account \(id, privacy: .private(mask: .hash))") // "Account <hash:3f9c…>"
/// ```
///
/// Values interpolated without `privacy:` are private, as in `os.Logger`,
/// unless their type is a ``LogPublicValue``: numbers, `Bool` and your own
/// conforming types. Literal text is always public. Engine-level privacy (``SystemLogger/Privacy``) and redaction
/// (``Redactor``) still apply to the whole rendered message.
public struct LogPrivacy: Sendable, Hashable {
    /// How a hidden value is replaced.
    public enum Mask: Sendable, Hashable {
        /// Replaced by `<private>` or `<sensitive>`.
        case none
        /// Replaced by a stable hash, `<hash:…>`, so the same value can be
        /// correlated across entries and launches. A hash of a short or guessable
        /// value (an email, a phone number) can be reversed by trying candidates,
        /// so use it for correlation, not secrecy.
        case hash
    }

    enum Kind: Sendable, Hashable {
        case `public`, `private`, sensitive
    }

    let kind: Kind
    /// How the value is replaced when it is hidden.
    public let mask: Mask

    /// Shown as is.
    public static let `public` = LogPrivacy(kind: .public, mask: .none)
    /// Shown as `<private>`, unless the registry reveals private values
    /// (``EngineRegistry/revealsPrivateValues``, for example in DEBUG builds).
    public static let `private` = LogPrivacy(kind: .private, mask: .none)
    /// Hidden like ``private``, with the given mask.
    public static func `private`(mask: Mask) -> LogPrivacy {
        LogPrivacy(kind: .private, mask: mask)
    }
    /// Shown as `<sensitive>`, always: never revealed, not even when the registry
    /// reveals private values. Use it for secrets, tokens and health data.
    public static let sensitive = LogPrivacy(kind: .sensitive, mask: .none)
    /// Hidden like ``sensitive``, with the given mask.
    public static func sensitive(mask: Mask) -> LogPrivacy {
        LogPrivacy(kind: .sensitive, mask: mask)
    }
}

/// A log message whose interpolated values can carry a ``LogPrivacy``.
///
/// You rarely name this type: every ``MoLogger`` level method takes one, and a
/// string literal becomes one. Literal text is public. An interpolated value is
/// private unless its type is a ``LogPublicValue`` or the call site says
/// `privacy: .public`:
///
/// ```swift
/// log.info("Signed in \(email) on \(device, privacy: .public)")
/// // → "Signed in <private> on iPhone"
/// log.info("Retry \(attempt) of \(limit)")   // numbers are public: "Retry 2 of 5"
/// ```
///
/// To log a `String` you already have, decide once: `"\(text)"` hides it, and
/// ``init(verbatim:)`` shows it.
///
/// The message is rendered once, when the entry passes the level filter, and
/// engines receive the rendered text in ``LogEntry/message``. Hidden values
/// never reach a ``LogEntry``, so no engine, file or remote shipper can see them.
public struct LogMessage: Sendable, Hashable, ExpressibleByStringInterpolation, CustomStringConvertible {
    /// The message with every non-public value replaced.
    private let redacted: String
    /// The message with private values shown and sensitive ones still replaced,
    /// or `nil` when the message has no private values. Always `nil` in release
    /// builds, where private values are never revealed.
    private let revealed: String?

    public init(stringLiteral value: String) {
        redacted = value
        revealed = nil
    }

    public init(stringInterpolation: StringInterpolation) {
        redacted = stringInterpolation.redacted
        revealed = stringInterpolation.revealed
    }

    /// A message made of `string`, all public. Use it to log a `String` you
    /// already have and know is safe to show; write `"\(string)"` to hide it.
    public init(verbatim string: String) {
        self.init(stringLiteral: string)
    }

    /// Whether the message has values marked ``LogPrivacy/private`` that
    /// ``rendered(revealingPrivateValues:)`` would show.
    public var hasPrivateValues: Bool { revealed != nil }

    /// The text engines receive. Private values are shown only when
    /// `revealingPrivateValues` is true; sensitive values never are.
    public func rendered(revealingPrivateValues: Bool = false) -> String {
        revealingPrivateValues ? (revealed ?? redacted) : redacted
    }

    /// The message with every non-public value hidden.
    public var description: String { redacted }

    // MARK: Interpolation

    /// Builds both renderings as the literal is read. The second string is only
    /// started at the first private value, and only in DEBUG builds, so a
    /// release build always costs the same as a `String` interpolation.
    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var redacted: String
        fileprivate var revealed: String?

        public init(literalCapacity: Int, interpolationCount: Int) {
            redacted = ""
            redacted.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: String) {
            redacted += literal
            revealed? += literal
        }

        /// A value without `privacy:`: private, shown as `<private>`. Mark it
        /// `privacy: .public`, or conform its type to ``LogPublicValue``, to show it.
        public mutating func appendInterpolation<T>(_ value: T) {
            appendInterpolation(value, privacy: .private)
        }

        /// A value whose type is declared safe to show: public. Picked over the
        /// unconstrained overload because it is more specific.
        public mutating func appendInterpolation<T: LogPublicValue>(_ value: T) {
            appendLiteral(String(describing: value))
        }

        /// A value with the given privacy.
        public mutating func appendInterpolation<T>(_ value: T, privacy: LogPrivacy) {
            switch privacy.kind {
            case .public:
                appendLiteral(String(describing: value))
            case .private:
                #if DEBUG
                // Only DEBUG builds can reveal private values, so only they keep
                // the second rendering.
                let text = String(describing: value)
                if revealed == nil { revealed = redacted }
                redacted += Self.placeholder(for: text, label: "private", mask: privacy.mask)
                revealed? += text
                #else
                redacted += Self.placeholder(for: value, label: "private", mask: privacy.mask)
                #endif
            case .sensitive:
                let placeholder = Self.placeholder(for: value, label: "sensitive", mask: privacy.mask)
                redacted += placeholder
                revealed? += placeholder
            }
        }

        /// Another message, keeping its hidden values hidden.
        public mutating func appendInterpolation(_ message: LogMessage) {
            if message.revealed != nil, revealed == nil { revealed = redacted }
            revealed? += message.revealed ?? message.redacted
            redacted += message.redacted
        }

        /// The text that replaces a hidden value. The value is only described
        /// when the mask needs it, so `<private>` costs no `String(describing:)`.
        private static func placeholder<T>(for value: T, label: String, mask: LogPrivacy.Mask) -> String {
            switch mask {
            case .none: return "<\(label)>"
            case .hash: return "<hash:\(LogMessage.stableHash(String(describing: value)))>"
            }
        }
    }

    /// 64-bit FNV-1a of the UTF-8 bytes, as 16 hex digits. Stable across
    /// launches and devices, unlike `Hasher`, so hashes can be correlated.
    static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}
