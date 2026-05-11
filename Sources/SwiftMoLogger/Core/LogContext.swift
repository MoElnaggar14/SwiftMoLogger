import Foundation

/// Task-scoped ambient log metadata.
///
/// Implemented via `@TaskLocal` so concurrent `Task`s cannot see each other's
/// context: each child task inherits the value at the point of detachment,
/// and `withValue` cleanly unwinds on return. Synchronous code inside the
/// `withValue` block sees the same value via Swift's task-local indirection.
public enum LogContext {
    @TaskLocal
    public static var current: LogMetadata = LogMetadata()
}
