import Foundation
@_exported import SwiftMoLogger

/// Compile-time logging helpers backed by Swift Macros.
///
/// Re-exports `SwiftMoLogger` so a single `import SwiftMoLoggerSugar`
/// gives you both the runtime API and the macros. Adopters who don't want
/// the `swift-syntax` build-time cost can stick to `import SwiftMoLogger`
/// and skip this product entirely.

#if swift(>=5.9)

/// Freestanding macro that captures the current source location at the
/// call site and logs through the given ``MoLogger``.
///
/// ```swift
/// #log(logger, "user signed in", level: .info, tag: .api)
/// ```
@freestanding(expression)
public macro log(
    _ logger: MoLogger,
    _ message: String,
    level: LogLevel = .info,
    tag: LogTag? = nil
) = #externalMacro(module: "SwiftMoLoggerMacros", type: "LogMacro")

/// Freestanding macro that wraps a block in ``Signposter/measure(_:tag:file:function:line:column:_:)``.
///
/// ```swift
/// let users = #measure(signposter, "loadUsers") {
///     try userRepo.all()
/// }
/// ```
@freestanding(expression)
public macro measure<T>(
    _ signposter: Signposter,
    _ name: StaticString,
    _ body: () throws -> T
) -> T = #externalMacro(module: "SwiftMoLoggerMacros", type: "MeasureMacro")

/// Member-attribute macro that wraps every method of an actor / class in
/// automatic entry+exit logging. Trace level on entry, error level on
/// thrown errors. The macro injects a stable signpost name per method.
///
/// The type must have a `logger: MoLogger` property (inject it); the
/// synthesised `__autoLog()` helper logs through it.
///
/// ```swift
/// @AutoLog
/// final class CheckoutService {
///     let logger: MoLogger
///     init(logger: MoLogger) { self.logger = logger }
///
///     func purchase(_ id: String) throws {
///         __autoLog()
///         …
///     }
/// }
/// ```
@attached(member, names: arbitrary)
@attached(memberAttribute)
public macro AutoLog() = #externalMacro(module: "SwiftMoLoggerMacros", type: "AutoLogMacro")

#endif
