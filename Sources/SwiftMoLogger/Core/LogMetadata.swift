import Foundation

/// Strongly-typed value attachable to a log entry as metadata.
///
/// Constrained to JSON-compatible primitives so entries serialize cleanly to
/// disk, network sinks, and analytics backends without bespoke encoders.
public enum LogMetadataValue: Sendable, Hashable, Codable, CustomStringConvertible {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case array([LogMetadataValue])
    case dictionary([String: LogMetadataValue])
    case null

    public var description: String {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .array(let value): return "[\(value.map(\.description).joined(separator: ", "))]"
        case .dictionary(let value):
            let pairs = value.map { "\($0.key): \($0.value.description)" }
            return "{\(pairs.joined(separator: ", "))}"
        case .null: return "null"
        }
    }
}

extension LogMetadataValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral,
                            ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral,
                            ExpressibleByNilLiteral, ExpressibleByArrayLiteral,
                            ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(nilLiteral: ()) { self = .null }
    public init(arrayLiteral elements: LogMetadataValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, LogMetadataValue)...) {
        self = .dictionary(Dictionary(uniqueKeysWithValues: elements))
    }
}

/// Ordered, copy-on-write metadata bag attached to log entries.
public struct LogMetadata: Sendable, Hashable, Codable, ExpressibleByDictionaryLiteral {
    public private(set) var storage: [String: LogMetadataValue]

    public init(_ storage: [String: LogMetadataValue] = [:]) {
        self.storage = storage
    }

    public init(dictionaryLiteral elements: (String, LogMetadataValue)...) {
        self.storage = Dictionary(uniqueKeysWithValues: elements)
    }

    public var isEmpty: Bool { storage.isEmpty }
    public var keys: Dictionary<String, LogMetadataValue>.Keys { storage.keys }

    public subscript(key: String) -> LogMetadataValue? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    /// Returns a new metadata bag with `other` merged on top of this one.
    /// Keys in `other` win — useful for layering request-scoped context onto a
    /// session-scoped baseline.
    public func merging(_ other: LogMetadata) -> LogMetadata {
        var copy = storage
        for (key, value) in other.storage {
            copy[key] = value
        }
        return LogMetadata(copy)
    }
}
