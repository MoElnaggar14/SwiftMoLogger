# 🚀 Setup Instructions

## Quick Start

### 1. Open the Project
Double-click `SwiftMoLoggerExampleApp.xcodeproj` to open in Xcode.

### 2. Add SwiftMoLogger Package Dependency

Since this example app demonstrates integration with your SwiftMoLogger package, you need to add the package dependency manually:

1. In Xcode, go to **File > Add Package Dependencies...**
2. Enter the package URL: `https://github.com/MoElnaggar14/SwiftMoLogger.git`
3. Click **Add Package**
4. Select the **SwiftMoLogger** product for the **SwiftMoLoggerExampleApp** target
5. Click **Add Package**

### 3. Build and Run
1. Select your target device or simulator (iPhone 15+ or iOS 15.0+)
2. Press **⌘+R** to build and run
3. Tap the demo buttons to see SwiftMoLogger in action!

## 📱 Demo Features

The app will show you:

- ✅ **App lifecycle logging** with proper MetricKit crash monitoring setup
- ✅ **Network operations** with request/response logging
- ✅ **User management** with authentication flow logging  
- ✅ **Analytics tracking** with event logging
- ✅ **Error handling** with graceful recovery logging
- ✅ **Performance monitoring** with timing and memory usage
- ✅ **Crash testing** (DEBUG only) to demonstrate crash reporting

## 🔧 Troubleshooting

### Package Resolution Issues
If you encounter package resolution issues:
1. Go to **File > Swift Packages > Reset Package Caches**
2. Clean build folder (**Product > Clean Build Folder**)
3. Try building again

### Simulator Issues
If the app doesn't run on simulator:
1. Make sure you're targeting iOS 15.0 or later
2. Try a different simulator device
3. Reset simulator if needed

### Import Errors
If you see `import SwiftMoLogger` errors:
1. Make sure you've added the package dependency correctly
2. Check that SwiftMoLogger appears in your project dependencies
3. Try refreshing the package dependencies

## 🎯 Next Steps

After running the example:
1. **Explore the code** - See how SwiftMoLogger is integrated
2. **Check the logs** - Watch Xcode console for logging output
3. **Test features** - Try all the demo buttons
4. **Integrate in your app** - Copy the patterns to your own project

Happy logging! 🪵✨