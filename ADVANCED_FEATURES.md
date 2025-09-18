# SwiftMoLogger Advanced Features

## Overview

SwiftMoLogger now provides a clean, thread-safe, and highly extensible logging architecture designed for production use. This document demonstrates advanced engine implementations and real-world patterns.

## Core Features

### Thread-Safe Architecture
- Concurrent queue with barrier writes for engine management
- Safe concurrent logging across multiple engines
- No performance bottlenecks or race conditions

### Extensible Engine System
- Simple `LogEngine` protocol with 3 methods: `info()`, `warn()`, `error()`  
- Automatic message distribution to all registered engines
- Easy engine registration and management

## Advanced Engine Examples

### 1. MemoryLogEngine - High-Performance In-Memory Logging

**Features:**
- Circular buffer with configurable max entries (default: 1000)
- Thread-safe concurrent access with barrier writes
- Built-in filtering and metrics (error count, recent logs)
- Zero file I/O overhead

**Use Cases:**
- Debug builds for immediate log inspection
- Performance-critical applications
- Temporary log buffering before network transmission

```swift
let memoryEngine = MemoryLogEngine(maxEntries: 500)
SwiftMoLogger.addEngine(memoryEngine)

// Later...
let recentErrors = memoryEngine.getAllLogs().filter { $0.level == "ERROR" }
let errorCount = memoryEngine.getErrorCount()
```

### 2. FileLogEngine - Production-Ready File Logging

**Features:**
- JSON-formatted log entries with timestamps and thread info
- Automatic log rotation when files exceed 1MB
- Background queue processing to avoid blocking
- Structured data perfect for log analysis tools

**Use Cases:**
- Production applications requiring persistent logs
- Integration with log aggregation systems (ELK, Splunk)
- Compliance and audit requirements

**Output Format:**
```json
{"timestamp":"2025-01-15 10:30:45.123","level":"ERROR","message":"Payment failed","thread":"background"}
```

### 3. NetworkLogEngine - Batched Remote Logging

**Features:**
- Intelligent batching (default: 10 logs per request)
- Background queue processing for non-blocking operation
- Structured payload with app metadata
- Automatic cleanup on deinitialization

**Use Cases:**
- Cloud-based log aggregation
- Real-time error monitoring
- Distributed system logging

**Payload Structure:**
```json
{
  "logs": [
    {
      "timestamp": "2025-01-15T10:30:45Z",
      "level": "ERROR", 
      "message": "Database timeout",
      "app_version": "1.0.0",
      "platform": "iOS"
    }
  ]
}
```

### 4. AnalyticsLogEngine - Error and Performance Tracking

**Features:**
- Selective logging (focuses on errors and performance issues)
- Real-time metrics collection
- Event tracking with properties
- Noise reduction (ignores routine info logs)

**Use Cases:**
- Application performance monitoring
- Error rate tracking
- Business intelligence and analytics
- A/B testing and feature monitoring

### 5. DebugLogEngine - Development-Focused Logging

**Features:**
- Conditional compilation (DEBUG builds only)
- Enhanced console output with timestamps and thread indicators
- Stack trace capture for errors
- Visual thread differentiation (🔵 main, 🟠 background)

**Use Cases:**
- Development and debugging
- QA testing builds
- Performance troubleshooting

## Production Architecture Patterns

### Multi-Engine Setup
```swift
// Recommended production setup
SwiftMoLogger.addEngine(FileLogEngine())          // Persistent storage
SwiftMoLogger.addEngine(NetworkLogEngine())       // Remote monitoring  
SwiftMoLogger.addEngine(AnalyticsLogEngine())     // Metrics collection

#if DEBUG
SwiftMoLogger.addEngine(DebugLogEngine())         // Enhanced debugging
SwiftMoLogger.addEngine(MemoryLogEngine())        // Quick inspection
#endif
```

### Tagged Logging for Component Separation
```swift
// Use semantic tags for better log organization
SwiftMoLogger.info("API request completed", tag: .network)
SwiftMoLogger.error("Database connection failed", tag: .database)
SwiftMoLogger.warn("UI rendering slow", tag: .performance)
```

### Error Handling Best Practices
```swift
// Critical errors - logged to all engines
SwiftMoLogger.error("🚨 Payment processing failed for order #\(orderId)")

// Performance issues - caught by analytics
SwiftMoLogger.info("⏱️ Database query took 2.5 seconds (performance issue)")

// Background operations - proper threading
DispatchQueue.global().async {
    SwiftMoLogger.info("📂 Background data sync completed")
}
```

## Performance Considerations

### Engine Selection
- **Memory Engine**: Fastest, use for high-frequency logging
- **File Engine**: Moderate overhead, asynchronous I/O  
- **Network Engine**: Highest latency, use batching
- **Analytics/Debug**: Minimal overhead, selective logging

### Threading Strategy
- All engines use background queues to avoid blocking main thread
- Barrier writes ensure thread safety without performance penalties
- Engine registry provides fast concurrent reads

### Resource Management
- Memory engine: Automatic circular buffer prevents memory leaks
- File engine: Log rotation prevents disk space issues  
- Network engine: Automatic cleanup flushes pending logs
- Registry: Reset functionality for testing and cleanup

## Migration and Compatibility

This advanced architecture maintains full backward compatibility:

```swift
// Existing code works unchanged
SwiftMoLogger.info("App started")
SwiftMoLogger.warn("Low memory")
SwiftMoLogger.error("Network failed")

// New features available when needed
SwiftMoLogger.addEngine(CustomEngine())
let engineCount = SwiftMoLogger.engineCount
SwiftMoLogger.reset()
```

## Testing and Debugging

### Memory Engine for Testing
```swift
// Perfect for unit tests - capture and verify logs
let testEngine = MemoryLogEngine()
SwiftMoLogger.addEngine(testEngine)

performOperation()

let logs = testEngine.getAllLogs()
XCTAssert(logs.contains { $0.message.contains("Expected log") })
```

### Debug Engine for Development  
```swift
// Enhanced debugging in development builds only
SwiftMoLogger.addEngine(DebugLogEngine())

// Output includes timestamps, threads, and stack traces
// 🔵 [14:30:15.123] ℹ️ User logged in
// 🟠 [14:30:15.456] 🚨 Network error
// 📍 Stack trace: MyApp.NetworkManager.request() + 42
```

## Conclusion

This enhanced SwiftMoLogger provides a clean, performant, and highly extensible logging solution suitable for production iOS applications. The architecture supports everything from simple console logging to sophisticated multi-engine distributed logging systems.

Key benefits:
- **Clean API**: Simple, intuitive interface
- **Thread-Safe**: Production-ready concurrent architecture  
- **Extensible**: Easy to add custom engines for any logging destination
- **Performance**: Optimized for high-throughput applications
- **Flexible**: Supports everything from debugging to production monitoring

The framework is ready for immediate use while providing a solid foundation for future logging requirements.