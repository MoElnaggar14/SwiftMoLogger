import Foundation

public extension URLRequest {
    /// The `URLProtocol` property SwiftMoLogger's network logger uses to skip
    /// a request. Also set on the requests it forwards, to avoid recursion.
    static let swiftMoLoggerExemptionKey = "swiftmologger.network.handled"

    /// Marks the request so `SwiftMoLoggerNetwork` doesn't log it.
    ///
    /// Log shippers must do this: otherwise, with network logging installed
    /// on the same session, every shipped batch produces new log entries to
    /// ship, forever.
    mutating func excludeFromNetworkLogging() {
        guard let mutable = (self as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return }
        URLProtocol.setProperty(true, forKey: Self.swiftMoLoggerExemptionKey, in: mutable)
        self = mutable as URLRequest
    }

    /// Whether ``excludeFromNetworkLogging()`` was applied.
    var isExcludedFromNetworkLogging: Bool {
        URLProtocol.property(forKey: Self.swiftMoLoggerExemptionKey, in: self) != nil
    }
}
