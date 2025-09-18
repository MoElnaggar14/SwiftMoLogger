# SwiftMoLogger Example iOS App

A comprehensive iOS application demonstrating all the advanced features of SwiftMoLogger in a real-world context.

## 🎯 Overview

This example app showcases SwiftMoLogger's multi-engine architecture in a production-like iOS application with a beautiful SwiftUI interface. Unlike the simple command-line demo, this app demonstrates how to integrate SwiftMoLogger into a real iOS app with multiple engines working simultaneously.

## ✨ Features Demonstrated

### 🏗️ **Multi-Engine Architecture**
- **System Logger**: Console output with emoji indicators
- **Memory Engine**: In-memory circular buffer for debugging (DEBUG builds only)
- **File Engine**: Persistent JSON logs in app documents directory
- **Analytics Engine**: Error and performance tracking with metrics
- **Debug Engine**: Enhanced console output with timestamps (DEBUG builds only)

### 📱 **Interactive Logging Interface**
- **Dashboard View**: Real-time engine status and statistics
- **Action Buttons**: Generate different types of logs interactively
- **Log Viewer**: Browse, filter, and search through memory logs
- **Settings Panel**: Configure engines and view analytics

### 🧪 **Realistic Scenarios**
- **Network Operations**: Simulated API calls with success/failure scenarios
- **Performance Testing**: Monitoring slow operations and bottlenecks
- **Background Tasks**: Async operations demonstrating thread-safe logging
- **Error Scenarios**: Various error conditions with proper categorization
- **Tagged Services**: `LogTagged` protocol examples for automatic context

## 🚀 Setup Instructions

### Option 1: Create New Xcode Project
1. Create a new iOS project in Xcode
2. Add SwiftMoLogger as a Swift Package dependency
3. Copy the files from `ExampleApp/` into your project
4. Build and run

### Option 2: Run as Standalone (from Package root)
1. Open Terminal in the SwiftMoLogger directory
2. Create an Xcode project file:
   ```bash
   swift package generate-xcodeproj
   ```
3. Open the generated project and add the ExampleApp files
4. Set the main target and run

### Required Files
- `SwiftMoLoggerExampleApp.swift` - Main app and engine configuration
- `ContentView.swift` - Main UI with dashboard and controls
- `LoggingDemoViewModel.swift` - Business logic and state management  
- `SupportingViews.swift` - Log viewer and settings sheets

## 🎮 How to Use

### 1. Launch the App
- The app automatically configures multiple logging engines on startup
- Check the console to see the initialization logs

### 2. Generate Logs
- Tap action buttons to generate different types of logs:
  - **Info**: General information and status updates
  - **Warning**: Non-critical issues and alerts
  - **Error**: Error conditions and failures
  - **Network Test**: Simulated API operations
  - **Performance**: Performance monitoring tests
  - **Background Task**: Async operations

### 3. View Real-time Statistics
- Monitor active engines count
- Track total logs, errors, and warnings
- See memory buffer status and file size

### 4. Explore Log Viewer
- Tap "View Logs" to see detailed log entries
- Filter by log level (All, INFO, WARN, ERROR)
- Search through log messages
- Clear logs when needed

### 5. Access Settings
- View detailed engine status
- Check analytics and statistics
- Generate test log sequences
- Test LogTagged services
- View log file information

## 🔧 Engine Configuration

The app demonstrates a production-ready engine setup:

```swift
// Production engines (always active)
SwiftMoLogger.addEngine(FileLogEngine())      // Persistent JSON logs
SwiftMoLogger.addEngine(AnalyticsLogEngine()) // Error tracking

#if DEBUG
// Development engines (DEBUG builds only)
SwiftMoLogger.addEngine(MemoryLogEngine(maxEntries: 500)) // Memory buffer
SwiftMoLogger.addEngine(DebugLogEngine())                 // Enhanced console
#endif
```

## 📊 **What You'll See**

### **Dashboard Features:**
- Real-time engine count and status indicators
- Live statistics (total logs, errors, warnings)
- Recent logs preview with color coding
- Engine status with descriptions and activity indicators

### **Log Viewer Features:**
- Filterable log list by level
- Search functionality across all messages
- Detailed timestamps and message formatting
- Color-coded log levels for easy identification

### **Settings Features:**
- Comprehensive engine statistics
- File logging information and size tracking
- Test log generation for demonstration
- LogTagged service examples
- Analytics reset and memory clearing

## 🏷️ **LogTagged Examples**

The app includes example services using the `LogTagged` protocol:

```swift
struct NetworkService: LogTagged {
    var logTag: LogTag { .network }
    
    func fetchUserData() {
        logInfo("🌐 Fetching user data from API") // Auto-tagged
        // ... implementation
    }
}

struct DatabaseService: LogTagged {
    var logTag: LogTag { .database }
    
    func saveUserSettings() {
        logInfo("💾 Saving user settings to database") // Auto-tagged
        // ... implementation  
    }
}
```

## 💡 **Production Integration Tips**

This example demonstrates patterns you can use in your own apps:

1. **Engine Configuration**: Set up different engines for DEBUG vs RELEASE builds
2. **Service Integration**: Use `LogTagged` protocol for automatic context
3. **Error Handling**: Proper error logging with meaningful messages
4. **Performance Monitoring**: Track slow operations and bottlenecks
5. **Background Logging**: Thread-safe logging in async operations
6. **User Feedback**: Optional log viewing for support and debugging

## 🎯 **Key Benefits Shown**

- **Thread-Safe**: All logging operations work seamlessly across main and background threads
- **Performance**: Background processing prevents UI blocking
- **Flexibility**: Easy to add/remove engines based on build configuration  
- **Debugging**: Memory logs perfect for development and testing
- **Production Ready**: File and analytics engines suitable for production apps
- **User Experience**: Logging doesn't impact app performance or responsiveness

## 📱 **Screenshots & Features**

The app provides a complete logging experience with:
- Beautiful SwiftUI interface
- Real-time updates and statistics
- Interactive log generation
- Comprehensive log management
- Production-ready architecture

This example serves as both a demonstration and a template for integrating SwiftMoLogger into your own iOS applications!