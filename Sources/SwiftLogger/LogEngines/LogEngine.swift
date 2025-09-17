import Foundation

/// Protocol defining the interface for logging engines
public protocol LogEngine {
    func info(message: String)
    func warn(message: String)
    func error(message: String)
}

/// Comprehensive logging tags organized by domain for better scalability and discoverability
public enum LogTag: String, CaseIterable {
    // Core System
    case `internal` = "[Internal]"
    case crash = "[Crash]"
    case performance = "[Performance]"
    case memory = "[Memory]"
    case lifecycle = "[Lifecycle]"
    
    // Network & Data
    case network = "[Network]"
    case download = "[Download]"
    case upload = "[Upload]"
    case parsing = "[Parsing]"
    case serialization = "[Serialization]"
    case api = "[API]"
    case websocket = "[WebSocket]"
    
    // Storage & Cache
    case cache = "[Cache]"
    case database = "[Database]"
    case coredata = "[CoreData]"
    case userdefaults = "[UserDefaults]"
    case keychain = "[Keychain]"
    case filesystem = "[FileSystem]"
    
    // UI & UX
    case ui = "[UI]"
    case animation = "[Animation]"
    case navigation = "[Navigation]"
    case accessibility = "[Accessibility]"
    case layout = "[Layout]"
    
    // Authentication & Security
    case authentication = "[Authentication]"
    case authorization = "[Authorization]"
    case biometrics = "[Biometrics]"
    case encryption = "[Encryption]"
    case security = "[Security]"
    
    // Third-party Services
    case firebase = "[Firebase]"
    case google = "[Google]"
    case analytics = "[Analytics]"
    case crashlytics = "[Crashlytics]"
    case notifications = "[Notifications]"
    
    // Business Logic
    case business = "[Business]"
    case validation = "[Validation]"
    case calculation = "[Calculation]"
    case workflow = "[Workflow]"
    
    // Development & Debug
    case debug = "[Debug]"
    case testing = "[Testing]"
    case mock = "[Mock]"
    case configuration = "[Configuration]"
    
    // External Integration
    case thirdparty = "[ThirdParty]"
    case webhook = "[Webhook]"
    case sync = "[Sync]"
    
    // Media & Assets
    case image = "[Image]"
    case video = "[Video]"
    case audio = "[Audio]"
    case assets = "[Assets]"
}

extension Array where Element == LogEngine {
    static let all: [Element] = local

    static let local: [Element] = [
        SystemLogger.main
    ]
}