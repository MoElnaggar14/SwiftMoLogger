import Foundation

/// A single user-action / lifecycle event recorded for crash context.
///
/// Mirrors the breadcrumb model used by Sentry / Bugsnag / Crashlytics so
/// shipping breadcrumbs to those backends is a one-shot mapping.
public struct Breadcrumb: Sendable, Hashable, Codable, Identifiable {
    public enum Category: String, Sendable, Codable {
        case navigation
        case userAction = "user_action"
        case lifecycle
        case network
        case state
        case custom
    }

    public let id: UUID
    public let timestamp: Date
    public let category: Category
    public let message: String
    public let metadata: LogMetadata

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        category: Category,
        message: String,
        metadata: LogMetadata = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.category = category
        self.message = message
        self.metadata = metadata
    }
}
