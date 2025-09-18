import UIKit
import SwiftMoLogger

// MARK: - AppDelegate with SwiftMoLogger Integration

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    
    // CRITICAL: Keep a strong reference to the crash reporter
    // This ensures it remains in memory for the app's lifetime
    private let crashReporter = EnhancedMetricKitReporter()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // STEP 1: Initialize crash monitoring EARLY in app launch
        setupCrashMonitoring()
        
        // STEP 2: Log app lifecycle events
        SwiftMoLogger.info(message: "App launch started", tag: LogTag.System.lifecycle)
        SwiftMoLogger.info(message: "iOS version: \(UIDevice.current.systemVersion)", tag: LogTag.System.lifecycle)
        SwiftMoLogger.info(message: "Device model: \(UIDevice.current.model)", tag: LogTag.System.lifecycle)
        
        // STEP 3: Setup the UI
        setupMainWindow()
        
        // STEP 4: Initialize app services with logging
        initializeAppServices()
        
        SwiftMoLogger.info(message: "App launch completed successfully", tag: LogTag.System.lifecycle)
        
        return true
    }
    
    // MARK: - Crash Monitoring Setup
    
    private func setupCrashMonitoring() {
        SwiftMoLogger.info(message: "Initializing crash monitoring", tag: LogTag.System.crash)
        SwiftMoLogger.info(message: "📱 Enhanced MetricKit crash reporting active (stores in app for viewing)", tag: LogTag.System.crash)
        SwiftMoLogger.info(message: "🔍 Crash reports saved in app and viewable via 'View Crash Reports' button", tag: LogTag.System.crash)
        
        // Start MetricKit crash monitoring
        crashReporter.startMonitoring()
        
        SwiftMoLogger.info(message: "Crash monitoring active", tag: LogTag.System.crash)
        SwiftMoLogger.crash(message: "App initialization - crash monitoring enabled")
        
        // Log information about crash reporting behavior
        SwiftMoLogger.info(message: "💡 To test: Use Crash Test → Restart app → Tap 'View Crash Reports'", tag: LogTag.System.crash)
    }
    
    // MARK: - UI Setup
    
    private func setupMainWindow() {
        SwiftMoLogger.info(message: "Setting up main window", tag: LogTag.ui)
        
        window = UIWindow(frame: UIScreen.main.bounds)
        
        // Create the main view controller
        let mainViewController = MainViewController()
        let navigationController = UINavigationController(rootViewController: mainViewController)
        
        window?.rootViewController = navigationController
        window?.makeKeyAndVisible()
        
        SwiftMoLogger.info(message: "Main window setup completed", tag: LogTag.ui)
    }
    
    // MARK: - App Services Initialization
    
    private func initializeAppServices() {
        SwiftMoLogger.info(message: "Initializing app services", tag: LogTag.System.lifecycle)
        
        // Initialize various app services with logging
        _ = NetworkManager.shared
        _ = UserManager.shared
        _ = AnalyticsManager.shared
        
        SwiftMoLogger.info(message: "All app services initialized", tag: LogTag.System.lifecycle)
    }
    
    // MARK: - App Lifecycle Events
    
    func applicationWillResignActive(_ application: UIApplication) {
        SwiftMoLogger.info(message: "App will resign active", tag: LogTag.System.lifecycle)
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        SwiftMoLogger.info(message: "App entered background", tag: LogTag.System.lifecycle)
        
        // Log background transition for analytics
        SwiftMoLogger.info(message: "Background transition event", tag: LogTag.ThirdParty.analytics)
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        SwiftMoLogger.info(message: "App will enter foreground", tag: LogTag.System.lifecycle)
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        SwiftMoLogger.info(message: "App became active", tag: LogTag.System.lifecycle)
        
        // Log app activation for analytics
        SwiftMoLogger.info(message: "App activation event", tag: LogTag.ThirdParty.analytics)
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        SwiftMoLogger.info(message: "App will terminate", tag: LogTag.System.lifecycle)
        
        // Clean shutdown
        crashReporter.stopMonitoring()
        SwiftMoLogger.info(message: "Crash monitoring stopped", tag: LogTag.System.crash)
    }
    
    // MARK: - Memory Warning
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        SwiftMoLogger.warn(message: "Memory warning received", tag: LogTag.System.memory)
        SwiftMoLogger.crash(message: "System memory pressure detected")
        
        // Log memory usage details
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let memoryUsage = Float(memoryInfo.resident_size) / 1024.0 / 1024.0
            SwiftMoLogger.warn(message: "Current memory usage: \(String(format: "%.1f", memoryUsage))MB", tag: LogTag.System.memory)
        }
    }
}
