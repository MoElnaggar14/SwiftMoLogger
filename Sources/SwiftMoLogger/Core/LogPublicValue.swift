/// A type whose `description` is safe to log.
///
/// SwiftMoLogger 5.0 makes values interpolated into a ``LogMessage`` without
/// `privacy:` private: they render as `<private>`. A conforming type is the
/// exception. Interpolated without `privacy:`, it's shown:
///
/// ```swift
/// enum CheckoutStep: String, LogPublicValue { case cart, payment, review }
///
/// log.info("Step \(step)")   // "Step payment", in 4.x and in 5.0
/// ```
///
/// In 4.x every unmarked value is still shown, so conforming a type changes
/// nothing yet. Conform your types now and run `audit_logging.py --privacy`
/// to see which interpolations 5.0 would hide.
///
/// The numeric types, `Bool`, `StaticString`, ``LogLevel``, ``LogTag`` and
/// optionals of them conform out of the box. `String`, `UUID`, `Date`, `URL`,
/// errors and collections don't: they often hold user data. Conform only types
/// whose every value is safe to show, such as enums of screens or states.
public protocol LogPublicValue {}

extension Int: LogPublicValue {}
extension Int8: LogPublicValue {}
extension Int16: LogPublicValue {}
extension Int32: LogPublicValue {}
extension Int64: LogPublicValue {}
extension UInt: LogPublicValue {}
extension UInt8: LogPublicValue {}
extension UInt16: LogPublicValue {}
extension UInt32: LogPublicValue {}
extension UInt64: LogPublicValue {}
extension Float: LogPublicValue {}
extension Double: LogPublicValue {}
extension Bool: LogPublicValue {}
extension StaticString: LogPublicValue {}
extension LogLevel: LogPublicValue {}
extension LogTag: LogPublicValue {}
extension Optional: LogPublicValue where Wrapped: LogPublicValue {}
