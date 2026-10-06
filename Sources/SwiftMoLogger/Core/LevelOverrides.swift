import Foundation

/// Minimum levels for parts of the app, keyed by ``LogTag/domain`` prefix.
///
/// A key matches its own domain and every domain below it: `"data"` covers
/// `data.database` and `data.cache`, but not `database`. When several keys match,
/// the longest wins, so `"data.database"` beats `"data"`.
///
/// An override can lower the threshold for one area (`trace` for the database
/// while the rest of the app logs `info`) or raise it (only errors from a noisy SDK).
/// Entries without a tag, or with a tag no key matches, use the registry's
/// ``EngineRegistry/minimumLevel``.
///
/// ```swift
/// logging.registry.levelOverrides = ["data.database": .trace, "thirdparty": .error]
/// ```
public struct LevelOverrides: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    private struct Rule: Sendable, Equatable {
        let domain: String
        /// `domain + "."`, built once so matching never allocates.
        let childPrefix: String
        let level: LogLevel
    }

    /// Sorted longest domain first, so the first match is the most specific.
    private var rules: [Rule] = []

    public init() {}

    public init(_ levels: [String: LogLevel]) {
        for (domain, level) in levels { self[domain] = level }
    }

    public init(dictionaryLiteral elements: (String, LogLevel)...) {
        for (domain, level) in elements { self[domain] = level }
    }

    public var isEmpty: Bool { rules.isEmpty }

    /// Every override, keyed by domain.
    public var levels: [String: LogLevel] {
        Dictionary(uniqueKeysWithValues: rules.map { ($0.domain, $0.level) })
    }

    /// The override set for exactly `domain` (not inherited from a parent).
    /// Setting `nil` removes it.
    public subscript(domain: String) -> LogLevel? {
        get { rules.first { $0.domain == domain }?.level }
        set {
            rules.removeAll { $0.domain == domain }
            guard let newValue, !domain.isEmpty else { return }
            rules.append(Rule(domain: domain, childPrefix: domain + ".", level: newValue))
            rules.sort { $0.domain.count > $1.domain.count }
        }
    }

    /// The level that applies to `domain`: the most specific matching override,
    /// otherwise `fallback`.
    public func minimumLevel(for domain: String?, fallback: LogLevel) -> LogLevel {
        guard let domain, !rules.isEmpty else { return fallback }
        for rule in rules where domain == rule.domain || domain.hasPrefix(rule.childPrefix) {
            return rule.level
        }
        return fallback
    }
}

public extension LogLevel {
    /// Parses a level name, case-insensitively: `"trace"`, `"debug"`, `"info"`,
    /// `"notice"`, `"warning"` (or `"warn"`), `"error"`, `"critical"`, `"fault"`.
    /// Returns nil for anything else, so a bad remote-config value is ignored
    /// rather than trapping.
    init?(name: String) {
        switch name.lowercased() {
        case "trace": self = .trace
        case "debug": self = .debug
        case "info": self = .info
        case "notice": self = .notice
        case "warning", "warn": self = .warning
        case "error": self = .error
        case "critical": self = .critical
        case "fault": self = .fault
        default: return nil
        }
    }
}
