# SwiftMoLogger Crash Reporting Architecture

This document explains the clean separation between production crash reporting and the demo/UI layer.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    PRODUCTION LAYER                         │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              MetricKitCrashReporter                 │    │
│  │  • Full MetricKit integration                       │    │
│  │  • Production-ready crash analysis                 │    │
│  │  • Signal detection & stack analysis               │    │
│  │  • Delegate pattern for extensibility              │    │
│  │  • Zero UI dependencies                            │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ CrashReportDelegate
                              │
┌─────────────────────────────────────────────────────────────┐
│                      UI/DEMO LAYER                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           EnhancedMetricKitReporter                 │    │
│  │  • Demo/UI integration only                        │    │
│  │  • Crash report caching for in-app viewing         │    │
│  │  • Sample data generation                          │    │
│  │  • UI-friendly crash report formatting             │    │
│  │  • Delegates all core functionality                │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Component Responsibilities

### MetricKitCrashReporter (Production)
**Location:** `Sources/SwiftMoLogger/MetricKit/MetricKitCrashReporter.swift`

**Purpose:** Production-ready crash reporting with zero dependencies on UI frameworks.

**Features:**
- ✅ MetricKit integration with full MXMetricManagerSubscriber protocol
- ✅ Comprehensive crash analysis (signals, call stacks, memory patterns)
- ✅ Extensible delegate pattern for external integrations
- ✅ Hang detection and reporting
- ✅ Production logging with SwiftMoLogger
- ✅ System-level crash detection (memory pressure, background kills, etc.)
- ✅ Thread-safe operation
- ✅ Zero UI framework dependencies

**API:**
```swift
let crashReporter = MetricKitCrashReporter()
crashReporter.crashReportDelegate = self // Optional
crashReporter.hangReportDelegate = self // Optional
crashReporter.startMonitoring()

// For testing only (DEBUG builds)
crashReporter.triggerTestCrash()
```

### EnhancedMetricKitReporter (Demo/UI)
**Location:** `SwiftMoLoggerExampleApp/EnhancedMetricKitReporter.swift`

**Purpose:** Demonstration layer showing how to build UI features on top of the production reporter.

**Features:**
- ✅ Uses production reporter as foundation
- ✅ Implements CrashReportDelegate to receive production crash reports
- ✅ Converts production reports to UI-friendly format
- ✅ Caches crash reports for in-app viewing
- ✅ Generates sample data for demonstration
- ✅ All core functionality delegated to production layer

**API:**
```swift
let demoReporter = EnhancedMetricKitReporter()
demoReporter.startMonitoring() // Delegates to production reporter
demoReporter.triggerTestCrash() // Delegates to production reporter
```

## Benefits of This Architecture

### 🎯 **Clean Separation**
- Production code has zero UI dependencies
- Demo code focuses purely on UI integration
- No code duplication between layers

### 🔧 **Maintainability**
- Single source of truth for crash reporting logic
- UI changes don't affect production reliability
- Easy to test production components in isolation

### 🚀 **Extensibility**
- Production reporter can be extended via delegates
- Multiple UI implementations can use the same foundation
- Easy to integrate with external crash reporting services

### 📱 **Production Ready**
- Production reporter is robust and battle-tested
- UI layer is clearly marked as demo/example only
- Developers know exactly what to use in production apps

## Usage in Production Apps

### Basic Usage
```swift
import SwiftMoLogger

@main
struct YourApp: App {
    private let crashReporter = MetricKitCrashReporter()
    
    init() {
        crashReporter.startMonitoring()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Advanced Usage with External Integration
```swift
class MyCrashService: CrashReportDelegate {
    func didReceiveCrashReport(_ report: [String: Any]) {
        // Send to external service (Firebase, Bugsnag, etc.)
        ExternalCrashService.submit(report)
        
        // Store locally for debugging
        LocalCrashStorage.save(report)
    }
}

let crashReporter = MetricKitCrashReporter()
let crashService = MyCrashService()
crashReporter.crashReportDelegate = crashService
crashReporter.startMonitoring()
```

## Demo App Features

The example app demonstrates:
- ✅ Crash report viewing UI
- ✅ Sample crash data for testing UI
- ✅ Integration patterns with production reporter
- ✅ Crash report caching and persistence
- ✅ User-friendly crash report formatting

## File Structure

```
SwiftMoLogger/
├── Sources/SwiftMoLogger/MetricKit/
│   └── MetricKitCrashReporter.swift          # Production reporter
├── SwiftMoLoggerExampleApp/
│   ├── EnhancedMetricKitReporter.swift       # Demo UI layer
│   ├── CrashReportModels.swift               # UI data models
│   └── CrashReportViewController.swift       # UI controllers
```

## Testing

### Production Reporter Testing
- Unit tests for crash analysis logic
- Integration tests with MetricKit mocks
- Signal detection validation
- Delegate notification testing

### Demo Layer Testing
- UI integration tests
- Crash report formatting validation
- Cache functionality testing
- Sample data generation testing

---

**Created by Mohammed Elnaggar (@MoElnaggar14)**  
**SwiftMoLogger v1.0**