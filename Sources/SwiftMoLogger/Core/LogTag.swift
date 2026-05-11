import Foundation

/// Domain tag attached to a log entry.
///
/// Tags carry a stable `rawValue` (the bracketed label rendered into the log
/// line) plus a `domain` identifier used for filtering. Built-in tags are
/// exposed via namespaces (`LogTag.Network.api`, …) so they remain
/// discoverable through code completion as the catalogue grows. Custom tags
/// can be created with ``LogTag/custom(_:domain:)``.
public struct LogTag: Sendable, Hashable, Codable, RawRepresentable, CustomStringConvertible {
    public let rawValue: String
    public let domain: String

    public init(rawValue: String) {
        self.rawValue = rawValue
        self.domain = LogTag.derivedDomain(from: rawValue)
    }

    public init(_ rawValue: String, domain: String) {
        self.rawValue = rawValue
        self.domain = domain
    }

    /// Build a custom tag at the call site.
    public static func custom(_ name: String, domain: String = "custom") -> LogTag {
        LogTag("[\(name)]", domain: domain)
    }

    public var description: String { rawValue }

    private static func derivedDomain(from rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return trimmed.isEmpty ? "general" : trimmed.lowercased()
    }
}

// MARK: - Catalogue

public extension LogTag {
    enum System {
        public static let crash = LogTag("[Crash]", domain: "system.crash")
        public static let performance = LogTag("[Performance]", domain: "system.performance")
        public static let memory = LogTag("[Memory]", domain: "system.memory")
        public static let lifecycle = LogTag("[Lifecycle]", domain: "system.lifecycle")
        public static let `internal` = LogTag("[Internal]", domain: "system.internal")
    }

    enum Network {
        public static let network = LogTag("[Network]", domain: "network")
        public static let api = LogTag("[API]", domain: "network.api")
        public static let download = LogTag("[Download]", domain: "network.download")
        public static let upload = LogTag("[Upload]", domain: "network.upload")
        public static let websocket = LogTag("[WebSocket]", domain: "network.websocket")
    }

    enum Data {
        public static let database = LogTag("[Database]", domain: "data.database")
        public static let cache = LogTag("[Cache]", domain: "data.cache")
        public static let coredata = LogTag("[CoreData]", domain: "data.coredata")
        public static let userdefaults = LogTag("[UserDefaults]", domain: "data.userdefaults")
        public static let keychain = LogTag("[Keychain]", domain: "data.keychain")
        public static let filesystem = LogTag("[FileSystem]", domain: "data.filesystem")
        public static let parsing = LogTag("[Parsing]", domain: "data.parsing")
        public static let serialization = LogTag("[Serialization]", domain: "data.serialization")
    }

    enum UI {
        public static let ui = LogTag("[UI]", domain: "ui")
        public static let navigation = LogTag("[Navigation]", domain: "ui.navigation")
        public static let animation = LogTag("[Animation]", domain: "ui.animation")
        public static let accessibility = LogTag("[Accessibility]", domain: "ui.accessibility")
        public static let layout = LogTag("[Layout]", domain: "ui.layout")
    }

    enum Security {
        public static let authentication = LogTag("[Authentication]", domain: "security.authentication")
        public static let authorization = LogTag("[Authorization]", domain: "security.authorization")
        public static let biometrics = LogTag("[Biometrics]", domain: "security.biometrics")
        public static let encryption = LogTag("[Encryption]", domain: "security.encryption")
        public static let security = LogTag("[Security]", domain: "security")
    }

    enum ThirdParty {
        public static let firebase = LogTag("[Firebase]", domain: "thirdparty.firebase")
        public static let analytics = LogTag("[Analytics]", domain: "thirdparty.analytics")
        public static let crashlytics = LogTag("[Crashlytics]", domain: "thirdparty.crashlytics")
        public static let notifications = LogTag("[Notifications]", domain: "thirdparty.notifications")
        public static let sync = LogTag("[Sync]", domain: "thirdparty.sync")
        public static let thirdparty = LogTag("[ThirdParty]", domain: "thirdparty")
    }

    enum Business {
        public static let business = LogTag("[Business]", domain: "business")
        public static let validation = LogTag("[Validation]", domain: "business.validation")
        public static let calculation = LogTag("[Calculation]", domain: "business.calculation")
        public static let workflow = LogTag("[Workflow]", domain: "business.workflow")
    }

    enum Development {
        public static let debug = LogTag("[Debug]", domain: "development.debug")
        public static let testing = LogTag("[Testing]", domain: "development.testing")
        public static let mock = LogTag("[Mock]", domain: "development.mock")
        public static let configuration = LogTag("[Configuration]", domain: "development.configuration")
    }

    enum Media {
        public static let image = LogTag("[Image]", domain: "media.image")
        public static let video = LogTag("[Video]", domain: "media.video")
        public static let audio = LogTag("[Audio]", domain: "media.audio")
        public static let assets = LogTag("[Assets]", domain: "media.assets")
    }
}

// MARK: - Convenience shorthands

public extension LogTag {
    /// Shorthands kept for source-compatibility with the v1 flat catalogue.
    static let crash = System.crash
    static let performance = System.performance
    static let memory = System.memory
    static let lifecycle = System.lifecycle
    static let network = Network.network
    static let api = Network.api
    static let download = Network.download
    static let upload = Network.upload
    static let websocket = Network.websocket
    static let database = Data.database
    static let cache = Data.cache
    static let coredata = Data.coredata
    static let userdefaults = Data.userdefaults
    static let keychain = Data.keychain
    static let filesystem = Data.filesystem
    static let parsing = Data.parsing
    static let serialization = Data.serialization
    static let ui = UI.ui
    static let navigation = UI.navigation
    static let animation = UI.animation
    static let accessibility = UI.accessibility
    static let layout = UI.layout
    static let authentication = Security.authentication
    static let authorization = Security.authorization
    static let biometrics = Security.biometrics
    static let encryption = Security.encryption
    static let security = Security.security
    static let firebase = ThirdParty.firebase
    static let analytics = ThirdParty.analytics
    static let crashlytics = ThirdParty.crashlytics
    static let notifications = ThirdParty.notifications
    static let sync = ThirdParty.sync
    static let thirdparty = ThirdParty.thirdparty
    static let business = Business.business
    static let validation = Business.validation
    static let calculation = Business.calculation
    static let workflow = Business.workflow
    static let debug = Development.debug
    static let testing = Development.testing
    static let mock = Development.mock
    static let configuration = Development.configuration
    static let image = Media.image
    static let video = Media.video
    static let audio = Media.audio
    static let assets = Media.assets
    static let webhook = LogTag("[Webhook]", domain: "external.webhook")
}
