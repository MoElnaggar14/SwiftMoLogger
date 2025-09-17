import Foundation

/// Default system logger that outputs to the console with emoji indicators
final class SystemLogger: LogEngine {
    static let main: SystemLogger = .init()
    private init() {}

    func info(message: String) {
        #if DEBUG
            debugPrint(message.withPrefix("ℹ️ "))
        #endif
    }

    func warn(message: String) {
        #if DEBUG
        debugPrint(message.withPrefix("⚠️ "))
        #endif
    }

    func error(message: String) {
        #if DEBUG
        debugPrint(message.withPrefix("🚨 "))
        #endif
    }
}
