import Foundation

/// A protocol for objects that can be tagged for logging purposes
///
/// Objects conforming to `LogTagged` automatically provide logging context,
/// making it easy to maintain consistent tagging across your application.
///
/// ## Example Usage
/// ```swift
/// class NetworkService: LogTagged {
///     var logTag: LogTag { LogTag.Network.api }
///     
///     func performRequest() {
///         logInfo("Request started")     // Automatically tagged with .api
///         logError("Request failed")     // Also automatically tagged
///     }
/// }
/// ```
public protocol LogTagged {
    var logTag: LogTag { get }
}

/// Extension providing namespace-style logging for better organization and IDE autocompletion
public extension LogTag {
    /// Core system logging namespace
    struct System {
        public static let `internal`: LogTag = .internal
        public static let crash: LogTag = .crash
        public static let performance: LogTag = .performance
        public static let memory: LogTag = .memory
        public static let lifecycle: LogTag = .lifecycle
    }
    /// Network and API logging namespace
    struct Network {
        public static let network: LogTag = .network
        public static let api: LogTag = .api
        public static let download: LogTag = .download
        public static let upload: LogTag = .upload
        public static let websocket: LogTag = .websocket
    }
    /// UI and UX logging namespace
    struct UserInterface {
        public static let ui: LogTag = .ui
        public static let navigation: LogTag = .navigation
        public static let animation: LogTag = .animation
        public static let accessibility: LogTag = .accessibility
        public static let layout: LogTag = .layout
    }
    /// Data and storage logging namespace
    struct Data {
        public static let cache: LogTag = .cache
        public static let database: LogTag = .database
        public static let coredata: LogTag = .coredata
        public static let userdefaults: LogTag = .userdefaults
        public static let keychain: LogTag = .keychain
        public static let filesystem: LogTag = .filesystem
        public static let parsing: LogTag = .parsing
        public static let serialization: LogTag = .serialization
    }
    /// Security and authentication logging namespace
    struct Security {
        public static let authentication: LogTag = .authentication
        public static let authorization: LogTag = .authorization
        public static let biometrics: LogTag = .biometrics
        public static let encryption: LogTag = .encryption
        public static let security: LogTag = .security
    }
    /// Third-party services logging namespace
    struct ThirdParty {
        public static let firebase: LogTag = .firebase
        public static let google: LogTag = .google
        public static let analytics: LogTag = .analytics
        public static let crashlytics: LogTag = .crashlytics
        public static let notifications: LogTag = .notifications
        public static let thirdparty: LogTag = .thirdparty
        public static let webhook: LogTag = .webhook
        public static let sync: LogTag = .sync
    }
    /// Business logic logging namespace
    struct Business {
        public static let business: LogTag = .business
        public static let validation: LogTag = .validation
        public static let calculation: LogTag = .calculation
        public static let workflow: LogTag = .workflow
    }
    /// Development and testing logging namespace
    struct Development {
        public static let debug: LogTag = .debug
        public static let testing: LogTag = .testing
        public static let mock: LogTag = .mock
        public static let configuration: LogTag = .configuration
    }
    /// Media and assets logging namespace
    struct Media {
        public static let image: LogTag = .image
        public static let video: LogTag = .video
        public static let audio: LogTag = .audio
        public static let assets: LogTag = .assets
    }
}

/// Extension for LogTagged objects to automatically provide logging context
public extension LogTagged {
    /// Log an info message with the object's tag
    /// - Parameter message: The message to log
    func logInfo(_ message: String) {
        SwiftMoLogger.info(message: message, tag: logTag)
    }
    /// Log a warning message with the object's tag
    /// - Parameter message: The message to log
    func logWarn(_ message: String) {
        SwiftMoLogger.warn(message: message, tag: logTag)
    }
    /// Log an error message with the object's tag
    /// - Parameter message: The message to log
    func logError(_ message: String) {
        SwiftMoLogger.error(message: message, tag: logTag)
    }
    /// Log a debug message with the object's tag
    /// - Parameter message: The message to log
    func logDebug(_ message: String) {
        SwiftMoLogger.debug(message: message, tag: logTag)
    }
}
