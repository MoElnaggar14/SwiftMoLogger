import Foundation

// MARK: - Log Tags

/// Comprehensive logging tags organized by domain
public enum LogTag: String, CaseIterable, Hashable, Codable {
    // MARK: - Core System
    case crash = "[Crash]"
    case performance = "[Performance]"
    case memory = "[Memory]"
    case lifecycle = "[Lifecycle]"

    // MARK: - Network & API
    case network = "[Network]"
    case api = "[API]"
    case download = "[Download]"
    case upload = "[Upload]"
    case websocket = "[WebSocket]"

    // MARK: - Data & Storage
    case database = "[Database]"
    case cache = "[Cache]"
    case coredata = "[CoreData]"
    case userdefaults = "[UserDefaults]"
    case keychain = "[Keychain]"
    case filesystem = "[FileSystem]"
    case parsing = "[Parsing]"
    case serialization = "[Serialization]"

    // MARK: - UI & User Experience
    case ui = "[UI]"
    case navigation = "[Navigation]"
    case animation = "[Animation]"
    case accessibility = "[Accessibility]"
    case layout = "[Layout]"

    // MARK: - Security & Authentication
    case authentication = "[Authentication]"
    case authorization = "[Authorization]"
    case biometrics = "[Biometrics]"
    case encryption = "[Encryption]"
    case security = "[Security]"

    // MARK: - Third-party Services
    case firebase = "[Firebase]"
    case analytics = "[Analytics]"
    case crashlytics = "[Crashlytics]"
    case notifications = "[Notifications]"
    case thirdparty = "[ThirdParty]"

    // MARK: - Business Logic
    case business = "[Business]"
    case validation = "[Validation]"
    case calculation = "[Calculation]"
    case workflow = "[Workflow]"

    // MARK: - Development & Debug
    case debug = "[Debug]"
    case testing = "[Testing]"
    case mock = "[Mock]"
    case configuration = "[Configuration]"

    // MARK: - Media & Assets
    case image = "[Image]"
    case video = "[Video]"
    case audio = "[Audio]"
    case assets = "[Assets]"

    // MARK: - External Integration
    case webhook = "[Webhook]"
    case sync = "[Sync]"
}
