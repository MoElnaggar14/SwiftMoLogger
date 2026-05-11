import Foundation

/// PII / secret scrubber for log entries.
///
/// Applies an ordered list of ``Rule``s to the entry's `message` and every
/// string-typed value inside `metadata`. The first matching rule wins per
/// substring.
///
/// Default rules cover the common cases: emails, JWT-shaped tokens, bearer
/// tokens, credit-card-shaped numbers, IPv4 addresses, phone numbers, and
/// AWS/GCP-style access keys. Adopters add more via ``Redactor/add(_:)``.
public struct Redactor: Sendable {
    public struct Rule: Sendable {
        public let name: String
        public let pattern: NSRegularExpression
        public let replacement: String

        public init(name: String, pattern: String, replacement: String = "[REDACTED]", options: NSRegularExpression.Options = [.caseInsensitive]) throws {
            self.name = name
            self.pattern = try NSRegularExpression(pattern: pattern, options: options)
            self.replacement = replacement
        }

        fileprivate init(name: String, regex: NSRegularExpression, replacement: String) {
            self.name = name
            self.pattern = regex
            self.replacement = replacement
        }
    }

    public private(set) var rules: [Rule]

    public init(rules: [Rule] = Redactor.defaultRules) {
        self.rules = rules
    }

    public mutating func add(_ rule: Rule) {
        rules.append(rule)
    }

    /// Apply every rule to `input`, returning the redacted string and the
    /// names of rules that fired (useful for tests / observability).
    public func redact(_ input: String) -> (output: String, hits: [String]) {
        var output = input
        var hits: [String] = []
        for rule in rules {
            let range = NSRange(output.startIndex..., in: output)
            let matches = rule.pattern.numberOfMatches(in: output, range: range)
            if matches > 0 {
                output = rule.pattern.stringByReplacingMatches(
                    in: output,
                    range: NSRange(output.startIndex..., in: output),
                    withTemplate: rule.replacement
                )
                hits.append(rule.name)
            }
        }
        return (output, hits)
    }

    /// Walk a ``LogMetadata`` bag and rewrite every string leaf.
    public func redact(_ metadata: LogMetadata) -> LogMetadata {
        var copy = metadata.storage
        for (key, value) in copy {
            copy[key] = redact(value)
        }
        return LogMetadata(copy)
    }

    private func redact(_ value: LogMetadataValue) -> LogMetadataValue {
        switch value {
        case .string(let raw):
            return .string(redact(raw).output)
        case .array(let arr):
            return .array(arr.map(redact))
        case .dictionary(let dict):
            return .dictionary(dict.mapValues(redact))
        case .int, .double, .bool, .null:
            return value
        }
    }
}

public extension Redactor {
    /// Curated defaults. Order matters: token rules come before generic
    /// patterns so we don't half-redact a JWT.
    static let defaultRules: [Rule] = {
        // Force-try is safe here — these are vetted compile-time-constant
        // patterns. A failure would be a programming error caught in tests.
        func rule(_ name: String, _ pattern: String, _ replacement: String = "[REDACTED]") -> Rule {
            // swiftlint:disable:next force_try
            try! Rule(name: name, pattern: pattern, replacement: replacement)
        }
        return [
            rule("jwt", #"eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+"#, "[JWT]"),
            rule("bearer", #"(?<=Bearer\s)[A-Za-z0-9\-._~+/]+=*"#, "[TOKEN]"),
            rule("basic_auth", #"(?<=Basic\s)[A-Za-z0-9+/=]+"#, "[BASIC]"),
            rule("aws_key", #"AKIA[0-9A-Z]{16}"#, "[AWS_KEY]"),
            rule("gcp_key", #"AIza[0-9A-Za-z\-_]{35}"#, "[GCP_KEY]"),
            rule("email", #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, "[EMAIL]"),
            rule("credit_card", #"\b(?:\d[ -]*?){13,16}\b"#, "[CARD]"),
            rule("phone", #"\+?\d{1,3}[\s\-]?\(?\d{2,4}\)?[\s\-]?\d{3,4}[\s\-]?\d{3,4}"#, "[PHONE]"),
            rule("ipv4", #"\b(?:\d{1,3}\.){3}\d{1,3}\b"#, "[IP]"),
            rule("uuid", #"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"#, "[UUID]")
        ]
    }()
}
