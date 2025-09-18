# SwiftMoLogger iOS Example App 📱

**A complete iOS application demonstrating how to integrate and use SwiftMoLogger in real-world scenarios.**

## 🎯 Overview

This example app shows developers exactly how to integrate **SwiftMoLogger** into their iOS applications with:

- ✅ **Complete app setup** with AppDelegate integration
- ✅ **MetricKit crash monitoring** configuration
- ✅ **Protocol-based logging** with LogTagged
- ✅ **Real-world service examples** (Network, User, Analytics)
- ✅ **Interactive UI** to test logging scenarios
- ✅ **Production-ready patterns** and best practices

## 🏗️ Project Structure

```
SwiftMoLoggerExampleApp/
├── SwiftMoLoggerExampleApp.xcodeproj/  # Xcode project files
├── SwiftMoLoggerExampleApp/
│   ├── AppDelegate.swift               # App setup with crash monitoring
│   ├── MainViewController.swift        # UI with demo scenarios
│   ├── NetworkManager.swift            # API logging examples
│   ├── Managers.swift                  # User & Analytics managers
│   └── Info.plist                      # App configuration
└── README.md                           # This file
```

## 🚀 Integration Steps

### Step 1: Add SwiftMoLogger Dependency to Your Xcode Project

In Xcode, go to:

1. **File > Add Package Dependencies...**
2. Enter the package URL: `https://github.com/MoElnaggar14/SwiftMoLogger.git`
3. Click **Add Package**
4. Select the **SwiftMoLogger** product
5. Click **Add Package**

### Step 2: Setup AppDelegate

```swift
import UIKit
import SwiftMoLogger

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    // CRITICAL: Keep strong reference to crash reporter
    private let crashReporter = MetricKitCrashReporter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // Initialize crash monitoring EARLY
        crashReporter.startMonitoring()
        
        // Log app lifecycle events
        SwiftMoLogger.info(message: "App launch started", tag: LogTag.System.lifecycle)
        SwiftMoLogger.info(message: "iOS version: \(UIDevice.current.systemVersion)", tag: LogTag.System.lifecycle)
        
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        SwiftMoLogger.info(message: "App will terminate", tag: LogTag.System.lifecycle)
        crashReporter.stopMonitoring()
    }
}
```

### Step 3: Implement LogTagged Protocol

```swift
import SwiftMoLogger

class NetworkManager: LogTagged {
    
    // Define primary logging context
    var logTag: LogTag { LogTag.Network.api }
    
    func fetchUserData() {
        logInfo("Starting user data fetch")  // Automatically tagged with .api
        
        // Use specific tags for complex operations
        SwiftMoLogger.info(message: "Making HTTP request", tag: LogTag.Network.network)
        SwiftMoLogger.info(message: "Parsing response", tag: LogTag.Data.parsing)
        
        logInfo("User data fetch completed")  // Back to automatic tagging
    }
}
```

## 📊 Demo Features

The example app includes interactive buttons to demonstrate:

### 🌐 Network Examples
- HTTP request logging with performance metrics
- Error handling and retry logic
- Response parsing and validation
- Upload progress tracking

### 👤 User Management Examples  
- Authentication flow logging
- Biometric authentication
- Session management
- User preference updates

### 📈 Analytics Examples
- Event tracking with properties
- Screen view logging
- Performance metrics
- Error tracking

### ⚠️ Error Handling Examples
- Network failure scenarios
- Graceful degradation
- Recovery procedures
- Fallback mechanisms

### 💥 Crash Testing
- MetricKit crash reporting demonstration
- Controlled crash scenarios (DEBUG only)
- System-level crash detection

### 📊 Performance Testing
- Operation timing measurement
- Memory usage monitoring
- Bottleneck detection
- Performance alerts

## 🏷️ Tag Organization Guide

### Hierarchical Structure
SwiftMoLogger organizes tags by domain for easy filtering:

```swift
// System Operations
SwiftMoLogger.info(message: "App initializing", tag: LogTag.System.lifecycle)
SwiftMoLogger.warn(message: "Memory warning", tag: LogTag.System.memory)
SwiftMoLogger.info(message: "Performance metric", tag: LogTag.System.performance)

// Network Operations
SwiftMoLogger.info(message: "API request", tag: LogTag.Network.api) 
SwiftMoLogger.error(message: "Connection failed", tag: LogTag.Network.network)
SwiftMoLogger.info(message: "Upload progress", tag: LogTag.Network.upload)

// Security Operations
SwiftMoLogger.info(message: "User authenticated", tag: LogTag.Security.authentication)
SwiftMoLogger.warn(message: "Suspicious activity", tag: LogTag.Security.security)
SwiftMoLogger.info(message: "Data encrypted", tag: LogTag.Security.encryption)
```

### Available Tag Namespaces

| **Domain** | **Examples** | **Use Cases** |
|------------|-------------|---------------|
| **System** | `.lifecycle`, `.memory`, `.performance` | App state, resources, metrics |
| **Network** | `.api`, `.network`, `.upload` | HTTP requests, connectivity |
| **Security** | `.authentication`, `.biometrics`, `.encryption` | Auth flows, sensitive operations |
| **Data** | `.database`, `.cache`, `.userdefaults` | Storage operations |
| **UI** | `.ui`, `.layout`, `.navigation` | User interface events |
| **Business** | `.workflow`, `.validation`, `.calculation` | App logic, rules |
| **ThirdParty** | `.analytics`, `.notifications`, `.sync` | External services |

## 🎓 Best Practices Demonstrated

### 1. Protocol-Based Context
```swift
class PaymentProcessor: LogTagged {
    var logTag: LogTag { LogTag.Security.encryption }
    
    func processPayment() {
        logInfo("Processing payment")           // Auto-tagged
        logError("Payment validation failed")  // Consistent context
    }
}
```

### 2. Critical Operation Logging
```swift
func criticalOperation() {
    SwiftMoLogger.crash(message: "Critical payment operation starting")
    // ... important code
    SwiftMoLogger.info(message: "Operation completed", tag: LogTag.Business.workflow)
}
```

### 3. Performance Monitoring
```swift
let startTime = CFAbsoluteTimeGetCurrent()
// ... perform operation
let duration = CFAbsoluteTimeGetCurrent() - startTime
SwiftMoLogger.info(message: "Operation took \(duration)s", tag: LogTag.System.performance)

if duration > 0.5 {
    SwiftMoLogger.warn(message: "Slow operation detected", tag: LogTag.System.performance)
}
```

### 4. Safe Error Logging
```swift
// ✅ Good: Log error without sensitive data
SwiftMoLogger.error(message: "Authentication failed for user", tag: LogTag.Security.authentication)

// ❌ Never: Log sensitive information
// SwiftMoLogger.error(message: "Password incorrect: \(password)")
```

### 5. Memory Warning Handling
```swift
func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
    SwiftMoLogger.warn(message: "Memory warning received", tag: LogTag.System.memory)
    SwiftMoLogger.crash(message: "System memory pressure detected")
    
    // Log memory cleanup actions
    SwiftMoLogger.info(message: "Clearing caches", tag: LogTag.Data.cache)
}
```

## 🔍 Console Output Analysis

The app produces rich, organized logging output:

```
ℹ️ [Crash] MetricKit crash monitoring started
ℹ️ [Lifecycle] App launch started
ℹ️ [Lifecycle] iOS version: 17.0
ℹ️ [Authentication] User login attempt initiated
🚨 [Crash] Critical authentication operation starting
ℹ️ [Validation] Validating username format
ℹ️ [Database] Checking user credentials
ℹ️ [Encryption] Generating session token
ℹ️ [Authentication] User login successful
ℹ️ [Analytics] User login event tracked
```

### Output Features:
- **🎨 Emoji indicators**: ℹ️ Info, ⚠️ Warning, 🚨 Error
- **🏷️ Tag-based filtering**: `[API]`, `[Database]`, `[Security]`
- **📊 Performance metrics**: Operation timings, memory usage
- **🔒 Security awareness**: No sensitive data logged
- **📱 Lifecycle tracking**: App state changes

## 🎯 Integration Checklist

### ✅ Basic Setup
- [ ] Add SwiftMoLogger package dependency in Xcode (File > Add Package Dependencies...)
- [ ] Import SwiftMoLogger in AppDelegate
- [ ] Initialize MetricKit crash monitoring in `didFinishLaunchingWithOptions`
- [ ] Keep strong reference to `MetricKitCrashReporter`

### ✅ Logging Implementation
- [ ] Implement `LogTagged` protocol in service classes
- [ ] Use appropriate tags for different operations
- [ ] Log app lifecycle events
- [ ] Add performance monitoring for critical operations

### ✅ Error Handling
- [ ] Log errors with appropriate context
- [ ] Implement graceful error recovery
- [ ] Never log sensitive data
- [ ] Use crash logging for critical operations

### ✅ Production Readiness
- [ ] Test crash reporting in DEBUG builds
- [ ] Verify log filtering works correctly
- [ ] Check memory usage impact
- [ ] Validate performance overhead

## 🔧 Customization Guide

### Adding Custom Tags
```swift
extension LogTag {
    struct YourDomain {
        static let feature1: LogTag = .custom("Feature1")
        static let feature2: LogTag = .custom("Feature2")
    }
}
```

### Custom Log Engines
```swift
struct RemoteLogEngine: LogEngine {
    func info(message: String) {
        // Send to remote logging service
    }
    
    func warn(message: String) {
        // Send warning to monitoring
    }
    
    func error(message: String) {
        // Send error to crash reporting
    }
}
```

## 🚀 Running the Example

### Prerequisites
- Xcode 14.0+ 
- iOS 15.0+ target device/simulator
- Swift 5.7+

### Quick Setup
⚡ **[See SETUP.md for detailed setup instructions](SETUP.md)**

### Build and Run
1. Open `SwiftMoLoggerExampleApp.xcodeproj` in Xcode
2. Add SwiftMoLogger package dependency (File > Add Package Dependencies...)
3. Select your target device/simulator
4. Build and run (⌘+R)
5. Tap demo buttons to see logging in action
6. Check Xcode console for logging output

### Testing Crash Reporting

**🔍 Important: MetricKit delivers crash reports on the NEXT app launch!**

#### Step-by-Step Crash Testing:
1. **Run in DEBUG mode** on simulator or device
2. **Tap "💥 Crash Test" button**
3. **Read the warning dialog** (explains the process)
4. **Confirm "💥 Crash App"** - app will crash immediately
5. **Restart the app** (this is when MetricKit delivers crash data)
6. **Tap "📊 View Crash Reports" button** - see detailed analysis in-app!
7. **No need to check Xcode console** - everything is in the app!

#### Expected Crash Report Output:
```
🚨 [Crash] 🚨 CRASH DETECTED 🚨
🚨 [Crash] App version: 1.0.0, iOS version: 17.0, Device: iPhone14,2
🚨 [Crash] Segmentation fault (SIGSEGV): Invalid memory access
ℹ️ [Crash] 🔍 Call Stack Analysis:
⚠️ [Crash] Memory access issue detected - likely accessing deallocated memory
ℹ️ [Crash] User/Third-party binaries in crash: SwiftMoLoggerExampleApp
ℹ️ [Crash] Crash report archived for further analysis
```

#### Why Next Launch?
MetricKit operates **outside your app's process** at the system level. It collects crash data after termination and delivers it when your app next launches. This captures crashes that traditional crash reporters miss!

## 📚 Learning Resources

After exploring this example:

1. **Read the logs** - Understand the tag-based organization
2. **Modify examples** - Add your own logging scenarios  
3. **Test crash reporting** - See MetricKit in action
4. **Implement in your app** - Follow the integration patterns
5. **Monitor performance** - Check logging overhead

## ⭐ Key Takeaways

1. **Early Initialization** - Start crash monitoring in `didFinishLaunchingWithOptions`
2. **Protocol-Based Context** - Use `LogTagged` for automatic tagging
3. **Hierarchical Organization** - Tags scale with app complexity
4. **Performance Awareness** - Monitor and log critical operations
5. **Security First** - Never log sensitive information
6. **Production Ready** - Minimal overhead, comprehensive coverage

---

## 🔗 Next Steps

Ready to integrate SwiftMoLogger in your own app?

1. **Copy integration patterns** from this example
2. **Adapt tag structure** to your app's architecture
3. **Implement crash monitoring** following the AppDelegate pattern
4. **Add performance logging** to critical operations
5. **Test thoroughly** before production deployment

**Happy Logging!** 🪵✨

---

**SwiftMoLogger Example App** | Created by Mohammed Elnaggar ([@MoElnaggar14](https://github.com/MoElnaggar14))