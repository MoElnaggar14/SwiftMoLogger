import Foundation

/// How much of a request URL a ``NetworkLogger`` writes to logs, breadcrumbs
/// and network events.
///
/// URLs often carry secrets: OAuth codes, signed-URL signatures, API keys in
/// query strings, `user:password@` credentials. Every policy except ``full``
/// drops user info.
public enum URLRedaction: Sendable, Hashable {
    /// Logs the URL exactly as sent. Only for local debugging.
    case full
    /// Keeps the query but replaces the values of the named items (any case)
    /// with `REDACTED`.
    case redactingQueryItems(Set<String>)
    /// Drops the query string and fragment entirely.
    case withoutQuery

    /// Query item names (lower-case) whose values are redacted by default.
    public static let defaultSensitiveQueryItems: Set<String> = [
        "access_token", "refresh_token", "id_token", "token", "code", "state",
        "api_key", "apikey", "key", "secret", "client_secret", "password", "pass",
        "auth", "session", "sessionid", "sig", "signature",
        "x-amz-signature", "x-amz-credential", "x-amz-security-token"
    ]

    /// Redacts ``defaultSensitiveQueryItems``.
    public static let `default` = URLRedaction.redactingQueryItems(defaultSensitiveQueryItems)

    /// The placeholder written in place of a redacted value.
    public static let placeholder = "REDACTED"

    /// Applies the policy.
    public func apply(to url: URL) -> URL {
        guard self != .full,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.user = nil
        components.password = nil

        switch self {
        case .full:
            break
        case .withoutQuery:
            components.percentEncodedQuery = nil
            components.percentEncodedFragment = nil
        case .redactingQueryItems(let names):
            let sensitive = Set(names.map { $0.lowercased() })
            components.percentEncodedQueryItems = components.percentEncodedQueryItems?.map { item in
                let name = (item.name.removingPercentEncoding ?? item.name).lowercased()
                guard sensitive.contains(name), item.value != nil else { return item }
                return URLQueryItem(name: item.name, value: Self.placeholder)
            }
        }
        return components.url ?? url
    }
}
