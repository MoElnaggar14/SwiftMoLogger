import UIKit
import SwiftMoLogger

class CrashReportDetailViewController: UIViewController {
    
    // MARK: - Properties
    private let crashReport: CrashReport
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    // MARK: - Initialization
    
    init(crashReport: CrashReport) {
        self.crashReport = crashReport
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        populateData()
        
        SwiftMoLogger.info(message: "CrashReportDetailViewController loaded", tag: LogTag.UserInterface.ui)
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        title = "Crash Details"
        view.backgroundColor = UIColor.systemGroupedBackground
        
        setupNavigationBar()
        setupScrollView()
    }
    
    private func setupNavigationBar() {
        // Share button
        let shareButton = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: self,
            action: #selector(shareButtonTapped)
        )
        navigationItem.rightBarButtonItem = shareButton
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func populateData() {
        let sections = [
            createOverviewSection(),
            createStackTraceSection(),
            createDeviceInfoSection(),
            createAdditionalInfoSection()
        ]
        
        var lastView: UIView? = nil
        
        for section in sections {
            contentView.addSubview(section)
            
            NSLayoutConstraint.activate([
                section.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                section.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16)
            ])
            
            if let lastView = lastView {
                section.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 16).isActive = true
            } else {
                section.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16).isActive = true
            }
            
            lastView = section
        }
        
        // Add bottom constraint
        lastView?.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -32).isActive = true
    }
}

// MARK: - Section Creation

extension CrashReportDetailViewController {
    
    private func createOverviewSection() -> UIView {
        let section = createSectionContainer()
        
        let headerLabel = createSectionHeader("Overview")
        section.addSubview(headerLabel)
        
        let crashReasonView = createInfoRow("Crash Reason", value: crashReport.crashReason, isHighlighted: true)
        let timestampView = createInfoRow("Timestamp", value: crashReport.formattedTimestamp)
        let appVersionView = createInfoRow("App Version", value: crashReport.appVersion)
        
        let stackView = UIStackView(arrangedSubviews: [crashReasonView, timestampView, appVersionView])
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        section.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: section.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -16),
            
            stackView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: section.bottomAnchor, constant: -16)
        ])
        
        return section
    }
    
    private func createStackTraceSection() -> UIView {
        let section = createSectionContainer()
        
        let headerLabel = createSectionHeader("Stack Trace")
        section.addSubview(headerLabel)
        
        let stackTraceLabel = UILabel()
        stackTraceLabel.text = crashReport.stackTrace
        stackTraceLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        stackTraceLabel.textColor = .label
        stackTraceLabel.numberOfLines = 0
        stackTraceLabel.backgroundColor = UIColor.tertiarySystemGroupedBackground
        stackTraceLabel.layer.cornerRadius = 6
        stackTraceLabel.layer.masksToBounds = true
        stackTraceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add some padding
        let containerView = UIView()
        containerView.backgroundColor = UIColor.tertiarySystemGroupedBackground
        containerView.layer.cornerRadius = 6
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackTraceLabel)
        
        NSLayoutConstraint.activate([
            stackTraceLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            stackTraceLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            stackTraceLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            stackTraceLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
        
        section.addSubview(containerView)
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: section.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -16),
            
            containerView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            containerView.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: section.bottomAnchor, constant: -16)
        ])
        
        return section
    }
    
    private func createDeviceInfoSection() -> UIView {
        let section = createSectionContainer()
        
        let headerLabel = createSectionHeader("Device Information")
        section.addSubview(headerLabel)
        
        let deviceModelView = createInfoRow("Device Model", value: crashReport.deviceModel)
        let osVersionView = createInfoRow("OS Version", value: crashReport.osVersion)
        
        let stackView = UIStackView(arrangedSubviews: [deviceModelView, osVersionView])
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        section.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: section.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -16),
            
            stackView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: section.bottomAnchor, constant: -16)
        ])
        
        return section
    }
    
    private func createAdditionalInfoSection() -> UIView {
        let section = createSectionContainer()
        
        let headerLabel = createSectionHeader("Additional Information")
        section.addSubview(headerLabel)
        
        let infoViews = crashReport.additionalInfo.map { key, value in
            createInfoRow(key, value: value)
        }
        
        let stackView = UIStackView(arrangedSubviews: infoViews)
        stackView.axis = .vertical
        stackView.spacing = 12
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        section.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: section.topAnchor, constant: 16),
            headerLabel.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 16),
            headerLabel.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -16),
            
            stackView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 12),
            stackView.leadingAnchor.constraint(equalTo: section.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: section.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: section.bottomAnchor, constant: -16)
        ])
        
        return section
    }
    
    // MARK: - Helper Methods
    
    private func createSectionContainer() -> UIView {
        let view = UIView()
        view.backgroundColor = UIColor.secondarySystemGroupedBackground
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
    
    private func createSectionHeader(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func createInfoRow(_ title: String, value: String, isHighlighted: Bool = false) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = .secondaryLabel
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        let valueLabel = UILabel()
        valueLabel.text = value
        valueLabel.font = UIFont.systemFont(ofSize: 15, weight: isHighlighted ? .semibold : .regular)
        valueLabel.textColor = isHighlighted ? .systemRed : .label
        valueLabel.numberOfLines = 0
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(titleLabel)
        container.addSubview(valueLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            valueLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            valueLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        
        return container
    }
    
    // MARK: - Actions
    
    @objc private func shareButtonTapped() {
        let reportText = generateReportText()
        
        let activityViewController = UIActivityViewController(
            activityItems: [reportText],
            applicationActivities: nil
        )
        
        // For iPad
        if let popover = activityViewController.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityViewController, animated: true)
        
        SwiftMoLogger.info(message: "User shared crash report", tag: LogTag.System.crash)
    }
    
    private func generateReportText() -> String {
        var text = "Crash Report\n\n"
        text += "Timestamp: \(crashReport.formattedTimestamp)\n"
        text += "App Version: \(crashReport.appVersion)\n"
        text += "Device: \(crashReport.deviceModel)\n"
        text += "OS Version: \(crashReport.osVersion)\n"
        text += "Crash Reason: \(crashReport.crashReason)\n\n"
        text += "Stack Trace:\n\(crashReport.stackTrace)\n\n"
        
        if !crashReport.additionalInfo.isEmpty {
            text += "Additional Information:\n"
            for (key, value) in crashReport.additionalInfo {
                text += "\(key): \(value)\n"
            }
        }
        
        return text
    }
}
