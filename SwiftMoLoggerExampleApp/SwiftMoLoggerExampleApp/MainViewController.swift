import UIKit
import SwiftMoLogger

// MARK: - Main View Controller

class MainViewController: UIViewController, LogTagged {
    
    // MARK: - LogTagged Protocol
    var logTag: LogTag { LogTag.ui }
    
    // MARK: - UI Elements
    private var titleLabel: UILabel!
    private var buttonStackView: UIStackView!
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        logInfo("Main view controller loaded")
        SwiftMoLogger.info(message: "Setting up main UI", tag: LogTag.layout)
        
        setupUI()
        
        SwiftMoLogger.info(message: "Main view setup completed", tag: LogTag.layout)
        logInfo("View controller ready for user interaction")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        logInfo("Main view will appear")
        SwiftMoLogger.info(message: "View transition animation started", tag: LogTag.animation)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        logInfo("Main view appeared")
        SwiftMoLogger.info(message: "View is visible to user", tag: LogTag.navigation)
        
        // Log screen view for analytics
        SwiftMoLogger.info(message: "Screen view: MainViewController", tag: LogTag.ThirdParty.analytics)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        logInfo("Main view will disappear")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        SwiftMoLogger.info(message: "Configuring view appearance", tag: LogTag.ui)
        
        view.backgroundColor = UIColor.systemBackground
        title = "SwiftMoLogger Demo"
        
        setupTitleLabel()
        setupButtons()
        
        logInfo("UI configuration completed")
    }
    
    private func setupTitleLabel() {
        SwiftMoLogger.info(message: "Setting up title label", tag: LogTag.layout)
        
        titleLabel = UILabel()
        view.addSubview(titleLabel)
        
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50)
        ])
        
        titleLabel.text = "🪵 SwiftMoLogger Example"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 24)
        titleLabel.textAlignment = .center
        
        SwiftMoLogger.info(message: "Title label configured", tag: LogTag.layout)
    }
    
    private func setupButtons() {
        SwiftMoLogger.info(message: "Setting up action buttons", tag: LogTag.layout)
        
        buttonStackView = UIStackView()
        view.addSubview(buttonStackView)
        
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonStackView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttonStackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            buttonStackView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            buttonStackView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
        
        buttonStackView.axis = .vertical
        buttonStackView.spacing = 16
        buttonStackView.alignment = .fill
        buttonStackView.distribution = .equalSpacing
        
        // Create demo buttons
        let buttons = [
            ("🌐 Network Example", #selector(networkExampleTapped)),
            ("👤 User Example", #selector(userExampleTapped)),
            ("📊 Analytics Example", #selector(analyticsExampleTapped)),
            ("⚠️ Error Example", #selector(errorExampleTapped)),
            ("💥 Crash Test", #selector(crashTestTapped)),
            ("📊 View Crash Reports", #selector(viewCrashReportsTapped)),
            ("📈 Performance Test", #selector(performanceTestTapped))
        ]
        
        for (title, action) in buttons {
            let button = createButton(title: title, action: action)
            buttonStackView.addArrangedSubview(button)
        }
        
        logInfo("All demo buttons created")
    }
    
    private func createButton(title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.backgroundColor = UIColor.systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        button.addTarget(self, action: action, for: .touchUpInside)
        
        // Log button creation for debugging
        SwiftMoLogger.debug(message: "Button created: \(title)", tag: LogTag.debug)
        
        return button
    }
    
    // MARK: - Button Actions
    
    @objc private func networkExampleTapped() {
        logInfo("Network example button tapped")
        
        SwiftMoLogger.info(message: "User initiated network example", tag: LogTag.ThirdParty.analytics)
        
        // Demonstrate network logging
        NetworkManager.shared.fetchUserData()
        
        showAlert(title: "Network Example", message: "Check console for network logging examples")
    }
    
    @objc private func userExampleTapped() {
        logInfo("User example button tapped")
        
        SwiftMoLogger.info(message: "User initiated user management example", tag: LogTag.ThirdParty.analytics)
        
        // Demonstrate user management logging
        UserManager.shared.simulateLogin(username: "demo_user")
        
        showAlert(title: "User Example", message: "Check console for user management logging examples")
    }
    
    @objc private func analyticsExampleTapped() {
        logInfo("Analytics example button tapped")
        
        // Demonstrate analytics logging
        AnalyticsManager.shared.trackEvent("demo_button_tapped", properties: [
            "button_type": "analytics_example",
            "screen": "main_view_controller"
        ])
        
        showAlert(title: "Analytics Example", message: "Check console for analytics logging examples")
    }
    
    @objc private func errorExampleTapped() {
        logInfo("Error example button tapped")
        
        SwiftMoLogger.info(message: "User initiated error simulation", tag: LogTag.ThirdParty.analytics)
        
        // Demonstrate error logging
        simulateError()
        
        showAlert(title: "Error Example", message: "Check console for error handling logging examples")
    }
    
    @objc private func crashTestTapped() {
        logInfo("Crash test button tapped")
        
        SwiftMoLogger.warn(message: "User initiated crash test", tag: LogTag.System.crash)
        SwiftMoLogger.crash(message: "Test crash simulation initiated by user")
        
        // Show warning before crash
        let alert = UIAlertController(
            title: "⚠️ MetricKit Crash Test",
            message: "This will crash the app to demonstrate MetricKit crash reporting.\n\n📍 New: Crash reports are stored in the app!\n\nSteps:\n1. Crash the app\n2. Restart the app\n3. Tap 'View Crash Reports' to see results\n4. No need to check Xcode console!",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            self.logInfo("User cancelled crash test")
        })
        
        alert.addAction(UIAlertAction(title: "💥 Crash App", style: .destructive) { _ in
            self.logInfo("User confirmed crash test - triggering crash")
            SwiftMoLogger.crash(message: "Intentional crash test starting")
            SwiftMoLogger.crash(message: "App will crash now - check logs on next launch")
            
            // Only crash in DEBUG builds
            #if DEBUG
            // Use the enhanced MetricKit crash reporter's test method
            let crashReporter = EnhancedMetricKitReporter()
            crashReporter.triggerTestCrash()
            #else
            self.showAlert(title: "Crash Test", message: "Crash test only available in DEBUG builds")
            #endif
        })
        
        present(alert, animated: true)
    }
    
    @objc private func viewCrashReportsTapped() {
        logInfo("View crash reports button tapped")
        
        SwiftMoLogger.info(message: "User requested crash report viewing", tag: LogTag.System.crash)
        
        // Navigate to the crash reports screen
        let crashReportsVC = CrashReportsViewController()
        let navController = UINavigationController(rootViewController: crashReportsVC)
        
        present(navController, animated: true) {
            SwiftMoLogger.info(message: "Crash reports screen presented", tag: LogTag.ui)
        }
    }
    
    @objc private func performanceTestTapped() {
        logInfo("Performance test button tapped")
        
        SwiftMoLogger.info(message: "User initiated performance test", tag: LogTag.ThirdParty.analytics)
        SwiftMoLogger.info(message: "Starting performance measurement", tag: LogTag.System.performance)
        
        // Demonstrate performance logging
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Simulate work
        for i in 0..<1000000 {
            _ = i * i
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        SwiftMoLogger.info(message: "Performance test completed in \(String(format: "%.3f", duration))s", tag: LogTag.System.performance)
        
        if duration > 0.1 {
            SwiftMoLogger.warn(message: "Performance test took longer than expected", tag: LogTag.System.performance)
        }
        
        showAlert(title: "Performance Test", message: "Check console for performance logging examples")
    }
    
    // MARK: - Helper Methods
    
    private func simulateError() {
        SwiftMoLogger.info(message: "Simulating network error", tag: LogTag.Network.network)
        
        // Simulate a network error scenario
        SwiftMoLogger.error(message: "Simulated API request failed", tag: LogTag.Network.api)
        SwiftMoLogger.warn(message: "Attempting retry with exponential backoff", tag: LogTag.Network.network)
        SwiftMoLogger.info(message: "Falling back to cached data", tag: LogTag.Data.cache)
        
        logWarn("Error simulation completed")
    }
    
    private func showAlert(title: String, message: String) {
        SwiftMoLogger.info(message: "Showing alert to user", tag: LogTag.ui)
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            SwiftMoLogger.info(message: "User dismissed alert", tag: LogTag.ui)
        })
        
        present(alert, animated: true) {
            SwiftMoLogger.info(message: "Alert presented to user", tag: LogTag.animation)
        }
    }
    
    
    // MARK: - Memory Management
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        
        logWarn("Memory warning received in view controller")
        SwiftMoLogger.warn(message: "View controller received memory warning", tag: LogTag.System.memory)
        
        // Log memory cleanup actions
        SwiftMoLogger.info(message: "Performing memory cleanup in view controller", tag: LogTag.System.memory)
    }
    
    deinit {
        logInfo("Main view controller deallocated")
        SwiftMoLogger.info(message: "View controller memory released", tag: LogTag.System.memory)
    }
}