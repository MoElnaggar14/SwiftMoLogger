# SwiftMoLogger 🚀

**Production-ready, thread-safe logging framework for iOS applications with advanced multi-engine architecture**

*Created by Mohammed Elnaggar (@MoElnaggar14)*

[![Swift Version](https://img.shields.io/badge/swift-5.7+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-iOS%2015.0%2B%20|%20macOS%2012.0%2B%20|%20tvOS%2015.0%2B%20|%20watchOS%208.0%2B-lightgrey.svg)](https://developer.apple.com)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

## 🎯 Overview

SwiftMoLogger is a clean, thread-safe, and highly extensible logging framework designed for production iOS applications. It features a unique multi-engine architecture that automatically distributes logs across multiple destinations while maintaining optimal performance and developer experience.

## 🆕 What's New in Version 2.0

**🎉 Major Release - Complete iOS Integration & Advanced Features**

- **📱 Ready-to-Run iOS App**: Complete SwiftUI example app with Xcode project
- **🏗️ Advanced Multi-Engine Demo**: See all 6 engines working together in real-time
- **📄 Native Document Viewer**: iOS-optimized log file viewer with share functionality
- **🔧 Production Patterns**: Proper DEBUG/RELEASE configurations demonstrated
- **🎨 Professional UI**: Modern SwiftUI interface with interactive logging demos
- **📊 Real-Time Analytics**: Live engine statistics and logging metrics
- **🛠️ Developer Tools**: Helper scripts and comprehensive documentation

## ✨ Key Features

- **🏗️ Multi-Engine Architecture**: Distribute logs to console, files, network, analytics, and custom destinations
- **🔒 Thread-Safe**: Concurrent queue with barrier writes - no race conditions or bottlenecks
- **⚡ High Performance**: Background processing, circular buffers, and optimized memory usage
- **🎯 Production-Ready**: JSON logging, automatic rotation, intelligent batching, error tracking
- **🧩 Clean API**: Simple, intuitive interface with powerful extensibility
- **📱 Modern Swift**: iOS 15+, built for scalability and maintainability

## 🚀 Quick Start

### Installation

```swift
dependencies: [
    .package(url: "https://github.com/MoElnaggar14/SwiftMoLogger.git", from: "2.0.0")
]
```

### Basic Logging - Works Out of the Box

```swift
import SwiftMoLogger

// Start logging immediately - SystemLogger included by default
SwiftMoLogger.info("🚀 Application started successfully")
SwiftMoLogger.warn("⚠️ Low memory warning detected")
SwiftMoLogger.error("❌ Network connection failed")

// Tagged logging for better organization
SwiftMoLogger.info("API request completed", tag: .network)
SwiftMoLogger.error("Database query timeout", tag: .database)
SwiftMoLogger.debug("Debug information", tag: .debug) // DEBUG builds only
```

### Multi-Engine Setup - Production Power

```swift
// Add advanced engines for production logging
SwiftMoLogger.addEngine(FileLogEngine())          // JSON file logging
SwiftMoLogger.addEngine(NetworkLogEngine())       // Remote log aggregation
SwiftMoLogger.addEngine(AnalyticsLogEngine())     // Error & performance tracking

#if DEBUG
SwiftMoLogger.addEngine(DebugLogEngine())         // Enhanced debugging
SwiftMoLogger.addEngine(MemoryLogEngine())        // In-memory log inspection
#endif

// Now all logs are automatically distributed to every engine
SwiftMoLogger.error("💥 Payment processing failed") 
// → Console + File + Network + Analytics + Debug + Memory

print("Active engines: \(SwiftMoLogger.engineCount)") // 6 engines
```

## 📦 Advanced Engine Features

SwiftMoLogger includes production-ready engines with sophisticated capabilities:

### 📝 MemoryLogEngine - High-Performance In-Memory Logging
```swift
let memoryEngine = MemoryLogEngine(maxEntries: 1000)
SwiftMoLogger.addEngine(memoryEngine)

// Later - inspect logs with built-in filtering
let recentLogs = memoryEngine.getRecentLogs(count: 10)
let errorCount = memoryEngine.getErrorCount()
let allLogs = memoryEngine.getAllLogs() // Thread-safe access
```
**Features:** Circular buffer, thread-safe concurrent access, built-in metrics, zero I/O overhead

### 💾 FileLogEngine - Production File Logging
```swift
SwiftMoLogger.addEngine(FileLogEngine()) // Writes to /tmp/swiftmologger_demo.log

// Produces structured JSON logs:
// {"timestamp":"2025-01-15 10:30:45.123","level":"ERROR","message":"Payment failed","thread":"background"}
```
**Features:** JSON formatting, automatic rotation (1MB), background processing, structured data for analysis

### 🌐 NetworkLogEngine - Batched Remote Logging
```swift
SwiftMoLogger.addEngine(NetworkLogEngine())
// Automatically batches and sends logs to remote endpoints
// Includes app metadata: version, platform, timestamps
```
**Features:** Intelligent batching (10 logs/request), background transmission, structured payloads, cleanup on exit

### 📊 AnalyticsLogEngine - Error & Performance Tracking
```swift
let analyticsEngine = AnalyticsLogEngine()
SwiftMoLogger.addEngine(analyticsEngine)

// Get real-time metrics
let metrics = analyticsEngine.getMetrics() // ["errors": 5, "warnings": 12]
```
**Features:** Selective logging (errors + performance), real-time metrics, noise reduction, event tracking

### 🔍 DebugLogEngine - Enhanced Development Logging
```swift
#if DEBUG
SwiftMoLogger.addEngine(DebugLogEngine())
// Output: 🔵 [14:30:15.123] ℹ️ User logged in
//         🟠 [14:30:15.456] 🚨 Network error + stack trace
#endif
```
**Features:** DEBUG-only compilation, enhanced console output, stack traces, thread indicators

## 📱 **iOS SwiftUI Example App - Production Ready!**

**🎉 NEW**: Complete, ready-to-run iOS application showcasing SwiftMoLogger's advanced features!

```
📁 ExampleApp/
├── 📱 SwiftMoLoggerExample.xcodeproj/          # Complete Xcode project
│   ├── project.pbxproj                        # Pre-configured with SwiftMoLogger
│   └── project.xcworkspace/
├── 📂 SwiftMoLoggerExample/                    # Source code folder
│   ├── SwiftMoLoggerExampleApp.swift          # App entry point with multi-engine setup
│   ├── ContentView.swift                      # Main dashboard with interactive buttons
│   ├── LoggingDemoViewModel.swift             # State management and business logic
│   ├── SupportingViews/
│   │   ├── LogViewerSheet.swift               # Native log file viewer
│   │   ├── SettingsSheet.swift                # Engine management and settings
│   │   └── DocumentViewer.swift               # iOS-native document viewer (iOS 15+)
│   └── Assets.xcassets/                       # App icons and colors
├── 🛠️ open_project.sh                        # Helper script for easy opening
└── 📖 README.md                               # Detailed setup and usage guide
```

### **🎯 What You Get:**
- **📱 Native iOS SwiftUI App**: Complete Xcode project ready to build and run
- **🏗️ Advanced Multi-Engine Demo**: All 6 engines working simultaneously (Console, File, Network, Analytics, Debug, Memory)
- **🎮 Interactive Testing Interface**: Buttons to generate different log scenarios and test cases
- **📊 Real-Time Dashboard**: Live engine statistics, error counts, and logging metrics
- **🔍 Advanced Log Viewer**: Native SwiftUI log file viewer with share functionality
- **⚙️ Production Configuration**: Proper DEBUG/RELEASE engine setup patterns
- **📱 iOS 15+ Compatible**: Uses ShareLink for iOS 16+ with UIActivityViewController fallback
- **🎨 Professional UI**: Modern SwiftUI design with proper navigation and state management

### **🚀 Quick Start (Ready-to-Run!):**
```bash
# Clone the repository
git clone https://github.com/MoElnaggar14/SwiftMoLogger.git
cd SwiftMoLogger

# Open the ready-made Xcode project
open ExampleApp/SwiftMoLoggerExample.xcodeproj

# Or use the helper script
./ExampleApp/open_project.sh
```

**That's it!** The project is pre-configured with:
- ✅ SwiftMoLogger package dependency already added
- ✅ iOS 15.0 minimum deployment target
- ✅ All source files properly organized
- ✅ Asset catalogs and app icons configured
- ✅ Ready to build and run on device or simulator

### **🧪 Demo Features:**
- **Log Generation**: Test different log levels (Info, Warning, Error) with realistic scenarios
- **Engine Statistics**: View real-time stats for all active logging engines
- **File Viewer**: Browse and share log files with native iOS document viewer
- **Settings Panel**: Manage engines, clear logs, and configure app settings
- **Multi-Engine Architecture**: See logs flowing to Console, File, Network, Analytics, Debug, and Memory engines
- **Production Patterns**: Examples of proper engine setup for different build configurations

---

## 🎯 **Command-Line Demo (Alternative)**

```bash
# Run the terminal demo to see core features
swift Demo.swift
```

**Command-line demo shows:**
- Multi-engine logging across 6 destinations
- Thread-safe concurrent operations
- JSON file logging and network batching
- Memory circular buffer with analytics

## 📋 Available Log Tags

SwiftMoLogger provides comprehensive tagging organized in namespaces for better discoverability:

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

SwiftMoLogger includes comprehensive crash reporting using Apple's MetricKit framework. This provides:

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

## 🔧 Extensible Architecture

SwiftMoLogger's greatest strength is its extensible architecture. You can easily add custom logging engines to send logs to different destinations.

### Built-in Engine

By default, SwiftMoLogger includes:
- **SystemLogger**: Outputs to console/Xcode debug area with emoji indicators

### Adding Custom Engines

```swift
// Create a custom engine that implements LogEngine protocol
class FileLogEngine: LogEngine {
    private let fileURL: URL
    
    init(fileURL: URL) {
        self.fileURL = fileURL
    }
    
    func info(message: String) {
        writeToFile("INFO: \(message)")
    }
    
    func warn(message: String) {
        writeToFile("WARN: \(message)")
    }
    
    func error(message: String) {
        writeToFile("ERROR: \(message)")
    }
    
    private func writeToFile(_ message: String) {
        // Your file writing implementation
    }
}

// Add the engine to SwiftMoLogger
let fileEngine = FileLogEngine(fileURL: logsFileURL)
SwiftMoLogger.addEngine(fileEngine)

// Now all logs go to both console and file
SwiftMoLogger.info(message: "This message goes everywhere!")
```

### Engine Management

```swift
// Check how many engines are registered
print("Total engines: \(SwiftMoLogger.engineCount)")

// Get all registered engines
let allEngines = SwiftMoLogger.getEngines()

// Remove a custom engine (SystemLogger cannot be removed)
SwiftMoLogger.removeEngine(at: 0) // Removes first custom engine
```

### Production-Ready Engine Examples

SwiftMoLogger includes advanced engine implementations in `Demo.swift`:

- **MemoryLogEngine**: High-performance circular buffer with filtering
- **FileLogEngine**: JSON-formatted logs with automatic rotation  
- **NetworkLogEngine**: Batched remote logging with retry logic
- **AnalyticsLogEngine**: Error and performance tracking
- **DebugLogEngine**: Enhanced debugging with stack traces

Run `swift Demo.swift` to see all advanced features in action!

### Multi-Engine Production Setup

```swift
// Recommended production configuration
SwiftMoLogger.addEngine(FileLogEngine())          // Persistent storage
SwiftMoLogger.addEngine(NetworkLogEngine())       // Remote monitoring
SwiftMoLogger.addEngine(AnalyticsLogEngine())     // Error tracking

#if DEBUG
SwiftMoLogger.addEngine(DebugLogEngine())         // Enhanced debugging
SwiftMoLogger.addEngine(MemoryLogEngine())        // Quick inspection
#endif

// Now all logs are distributed to multiple destinations
SwiftMoLogger.info("🚀 Multi-engine logging active")
```

### Advanced Features

- **Thread-Safe**: Concurrent engine access with barrier writes
- **Performance Optimized**: Background queues prevent UI blocking
- **Memory Efficient**: Circular buffers and automatic cleanup
- **Production Ready**: JSON logging, rotation, batching, analytics
- **Extensible**: Simple protocol-based architecture

See `ADVANCED_FEATURES.md` for comprehensive documentation.

## 🏗️ Clean Architecture

SwiftMoLogger avoids API bloat through smart design choices:

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

SwiftMoLogger is available under the MIT license. See the LICENSE file for more info.

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