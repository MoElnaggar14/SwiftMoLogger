# SwiftLogger 📱🪵

A comprehensive, scalable logging framework for iOS applications with built-in crash reporting using Apple's MetricKit.

[![Swift Version](https://img.shields.io/badge/swift-5.7+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2015.0%2B%20|%20macOS%2012.0%2B%20|%20tvOS%2015.0%2B%20|%20watchOS%208.0%2B-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 🌟 Features

- 🪵 **Multi-level logging**: Info, Warning, Error levels with emoji indicators
- 🏷️ **Scalable tagged logging**: 40+ organized tags by domain
- 🔍 **MetricKit crash reporting**: System-level crash debugging
- 📦 **Protocol-based logging**: Automatic context with `LogTagged`
- 🎯 **Namespace organization**: IDE-friendly tag discovery
- 🚀 **Modern Swift**: iOS 15+ with async/await support
- ⚡ **Zero dependencies**: Lightweight and fast
- 🔧 **Extensible**: Pluggable logging engines

## 🚀 Quick Start

### Installation

Add SwiftLogger to your Swift Package Manager dependencies:

```swift
dependencies: [
    .package(url: "https://github.com/MoElnaggar14/SwiftLogger.git", from: "1.0.0")
]
```

### Basic Usage

```swift
import SwiftLogger

// Basic logging
SwiftLogger.info(message: "App started successfully")
SwiftLogger.warn(message: "Low memory warning")
SwiftLogger.error(message: "Failed to load data")

// Tagged logging (traditional approach)
SwiftLogger.info(message: "Request started", tag: .network)
SwiftLogger.error(message: "Cache miss", tag: .cache)

// Namespace approach (recommended)
SwiftLogger.info(message: "API request started", tag: LogTag.Network.api)
SwiftLogger.warn(message: "View layout issue", tag: LogTag.UI.layout)
SwiftLogger.error(message: "Database error", tag: LogTag.Data.database)
SwiftLogger.debug(message: "Debug info", tag: LogTag.Development.debug)

// Crash-specific logging
SwiftLogger.crash(message: "Critical operation starting")
```

### Object-Based Logging with LogTagged

For better organization, objects can conform to `LogTagged` for automatic context:

```swift
class NetworkManager: LogTagged {
    var logTag: LogTag { LogTag.Network.api }
    
    func fetchData() {
        logInfo("Starting data fetch") // Automatically tagged with .api
        // ... network logic
        logError("Failed to fetch data") // Also automatically tagged
    }
}

struct DatabaseService: LogTagged {
    var logTag: LogTag { LogTag.Data.database }
    
    func save() {
        logInfo("Saving to database")
        // ... save logic
        logDebug("Save operation completed")
    }
}
```

### MetricKit Crash Reporting

```swift
import SwiftLogger

@main
struct YourApp: App {
    // Create and retain the crash reporter instance
    private let crashReporter = MetricKitCrashReporter()
    
    init() {
        // Enable MetricKit crash monitoring
        crashReporter.startMonitoring()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

## 📋 Available Log Tags

SwiftLogger provides comprehensive tagging organized in namespaces for better discoverability:

### Core System
- `LogTag.System.internal` - Internal framework operations
- `LogTag.System.crash` - Crash-related logging
- `LogTag.System.performance` - Performance monitoring
- `LogTag.System.memory` - Memory usage and warnings
- `LogTag.System.lifecycle` - App lifecycle events

### Network & Data
- `LogTag.Network.network` - Network requests
- `LogTag.Network.api` - API communications
- `LogTag.Network.download` / `.upload` - File transfers
- `LogTag.Network.websocket` - WebSocket connections
- `LogTag.Data.parsing` - Data parsing operations
- `LogTag.Data.serialization` - Data serialization

### Storage & Cache
- `LogTag.Data.cache` - Caching operations
- `LogTag.Data.database` - Database operations
- `LogTag.Data.coredata` - Core Data operations
- `LogTag.Data.userdefaults` - UserDefaults operations
- `LogTag.Data.keychain` - Keychain operations
- `LogTag.Data.filesystem` - File system operations

### UI & UX
- `LogTag.UI.ui` - User interface operations
- `LogTag.UI.navigation` - Navigation events
- `LogTag.UI.animation` - Animation operations
- `LogTag.UI.accessibility` - Accessibility features
- `LogTag.UI.layout` - Layout operations

### Security & Authentication
- `LogTag.Security.authentication` - Authentication flows
- `LogTag.Security.authorization` - Authorization checks
- `LogTag.Security.biometrics` - Biometric authentication
- `LogTag.Security.encryption` - Encryption operations
- `LogTag.Security.security` - Security-related events

### Third-party & External
- `LogTag.ThirdParty.firebase` - Firebase operations
- `LogTag.ThirdParty.analytics` - Analytics events
- `LogTag.ThirdParty.crashlytics` - Crashlytics integration
- `LogTag.ThirdParty.notifications` - Push notifications
- `LogTag.ThirdParty.sync` - Data synchronization

### Business Logic
- `LogTag.Business.business` - Business logic operations
- `LogTag.Business.validation` - Data validation
- `LogTag.Business.calculation` - Calculations
- `LogTag.Business.workflow` - Workflow operations

### Development
- `LogTag.Development.debug` - Debug information (DEBUG only)
- `LogTag.Development.testing` - Testing operations
- `LogTag.Development.mock` - Mock data operations
- `LogTag.Development.configuration` - Configuration changes

### Media & Assets
- `LogTag.Media.image` / `.video` / `.audio` - Media operations
- `LogTag.Media.assets` - Asset management

## 🔥 MetricKit Crash Reporting

SwiftLogger includes comprehensive crash reporting using Apple's MetricKit framework. This provides:

- **System-level crash collection** - Works outside your app's process
- **Detailed crash analysis** - Signal interpretation and pattern detection
- **Automatic crash categorization** - Common crash types identified
- **Call stack analysis** - Focus on user code
- **iOS version optimized** - Immediate delivery on iOS 15+

### Key Benefits
- Captures crashes traditional reporters miss
- Memory pressure crashes
- Background termination crashes
- Watchdog timeout crashes
- Kernel-level terminations

### Example Output
```
🚨 [Crash] 🚨 CRASH DETECTED 🚨
🚨 [Crash] App version: 1.0.0, iOS version: 15.0, Device: iPhone14,2
🚨 [Crash] Segmentation fault (SIGSEGV): Invalid memory access
ℹ️ [Crash] 🔍 Call Stack Analysis:
⚠️ [Crash] Memory access issue detected - likely accessing deallocated memory
ℹ️ [Crash] User/Third-party binaries in crash: YourApp
```

## 🏗️ Scalable Architecture

SwiftLogger avoids API bloat through smart design choices:

### ✅ Scalable Approach
- **Namespace organization** - `LogTag.Network.api` instead of individual methods
- **Protocol-based logging** - Automatic context with `LogTagged`
- **Flexible API** - Single `info(message:tag:)` for all scenarios
- **No method explosion** - New tags don't create new methods

### ❌ What We Avoid
- Bloated convenience methods for every tag
- Hard-to-discover APIs
- Method explosion as tags grow
- Inconsistent logging patterns

## 📖 Advanced Usage

### Custom Log Engines

```swift
struct CustomLogEngine: LogEngine {
    func info(message: String) {
        // Custom info logging implementation
    }
    
    func warn(message: String) {
        // Custom warning logging implementation
    }
    
    func error(message: String) {
        // Custom error logging implementation
    }
}
```

### Testing Crash Reporting

```swift
#if DEBUG
let crashReporter = MetricKitCrashReporter()
crashReporter.startMonitoring()
crashReporter.triggerTestCrash() // ⚠️ This will actually crash your app!
#endif
```

## 📋 Requirements

- iOS 15.0+ / macOS 12.0+ / tvOS 15.0+ / watchOS 8.0+
- Swift 5.7+
- Xcode 14.0+

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

SwiftLogger is available under the MIT license. See the LICENSE file for more info.

## 👨‍💻 Author

**Mohammed Elnaggar**
- GitHub: [@MoElnaggar14](https://github.com/MoElnaggar14)
- Twitter: [@MoElnaggar14](https://twitter.com/MoElnaggar14)

## 🙏 Acknowledgments

- Inspired by modern iOS logging needs
- MetricKit integration follows Apple's best practices
- Built with scalability and developer experience in mind

---

⭐ **Star this repo if you find it helpful!** ⭐