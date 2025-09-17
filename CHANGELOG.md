# Changelog

All notable changes to SwiftLogger will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-17

### Added
- 🎉 **Initial public release of SwiftLogger**
- 🪵 **Multi-level logging** with info, warn, error levels
- 🏷️ **Comprehensive tag system** with 40+ organized tags by domain
- 🔍 **MetricKit crash reporting** with system-level crash debugging
- 📦 **LogTagged protocol** for automatic context logging
- 🎯 **Namespace organization** for better IDE discoverability
- ⚡ **Zero dependencies** lightweight framework
- 🔧 **Extensible architecture** with pluggable logging engines
- 🚀 **Modern Swift support** for iOS 15+ with async/await
- 📱 **Multi-platform support** for iOS, macOS, tvOS, watchOS
- 🧪 **Comprehensive test suite** with XCTest integration
- 📖 **Detailed documentation** and examples

### Features
- **Scalable Architecture**: Namespace-based tag organization prevents API bloat
- **MetricKit Integration**: Captures crashes traditional reporters miss
- **Protocol-Based Logging**: Objects can conform to `LogTagged` for automatic context
- **Signal Interpretation**: Human-readable crash signal descriptions
- **Pattern Detection**: Automatic identification of common crash types
- **Debug Support**: Debug-only logging with compile-time safety
- **Emoji Indicators**: Visual distinction between log levels (ℹ️ ⚠️ 🚨)

### Architecture Highlights
- **No Singleton Pattern**: Instance-based crash reporter for better testability
- **Namespace Organization**: `LogTag.Network.api` instead of bloated convenience methods
- **Flexible API**: Single `info(message:tag:)` method for all scenarios
- **Extensible Design**: Easy to add new tags without breaking changes

### Supported Platforms
- iOS 15.0+
- macOS 12.0+
- tvOS 15.0+
- watchOS 8.0+

### Swift Support
- Swift 5.7+
- Xcode 14.0+

[1.0.0]: https://github.com/MoElnaggar14/SwiftLogger/releases/tag/1.0.0