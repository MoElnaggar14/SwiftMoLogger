import UIKit

class CrashReportTableViewCell: UITableViewCell {
    
    // MARK: - UI Components
    private let titleLabel = UILabel()
    private let timestampLabel = UILabel()
    private let reasonLabel = UILabel()
    private let stackTraceLabel = UILabel()
    private let deviceInfoLabel = UILabel()
    private let severityIndicator = UIView()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        selectionStyle = .none
        backgroundColor = .clear
        
        setupLabels()
        setupSeverityIndicator()
        setupConstraints()
    }
    
    private func setupLabels() {
        // Title Label
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Timestamp Label
        timestampLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        timestampLabel.textColor = .secondaryLabel
        timestampLabel.numberOfLines = 1
        timestampLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Reason Label
        reasonLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        reasonLabel.textColor = .systemOrange
        reasonLabel.numberOfLines = 1
        reasonLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Stack Trace Label
        stackTraceLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        stackTraceLabel.textColor = .tertiaryLabel
        stackTraceLabel.numberOfLines = 2
        stackTraceLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Device Info Label
        deviceInfoLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        deviceInfoLabel.textColor = .quaternaryLabel
        deviceInfoLabel.numberOfLines = 1
        deviceInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add to content view
        contentView.addSubview(titleLabel)
        contentView.addSubview(timestampLabel)
        contentView.addSubview(reasonLabel)
        contentView.addSubview(stackTraceLabel)
        contentView.addSubview(deviceInfoLabel)
    }
    
    private func setupSeverityIndicator() {
        severityIndicator.layer.cornerRadius = 3
        severityIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(severityIndicator)
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            // Severity Indicator
            severityIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            severityIndicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            severityIndicator.widthAnchor.constraint(equalToConstant: 6),
            severityIndicator.heightAnchor.constraint(equalToConstant: 40),
            
            // Title Label
            titleLabel.leadingAnchor.constraint(equalTo: severityIndicator.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: timestampLabel.leadingAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            
            // Timestamp Label
            timestampLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timestampLabel.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            timestampLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            
            // Reason Label
            reasonLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            reasonLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            reasonLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            
            // Stack Trace Label
            stackTraceLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            stackTraceLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stackTraceLabel.topAnchor.constraint(equalTo: reasonLabel.bottomAnchor, constant: 4),
            
            // Device Info Label
            deviceInfoLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            deviceInfoLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            deviceInfoLabel.topAnchor.constraint(equalTo: stackTraceLabel.bottomAnchor, constant: 4),
            deviceInfoLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }
    
    // MARK: - Configuration
    
    func configure(with crashReport: CrashReport) {
        titleLabel.text = "App Crash - \(crashReport.appVersion)"
        timestampLabel.text = formatTimestamp(crashReport.timestamp)
        reasonLabel.text = crashReport.crashReason
        stackTraceLabel.text = crashReport.shortDescription
        deviceInfoLabel.text = "\(crashReport.deviceModel) • \(crashReport.osVersion)"
        
        // Set severity indicator color based on crash reason
        severityIndicator.backgroundColor = getSeverityColor(for: crashReport.crashReason)
        
        // Add subtle background for better visual separation
        contentView.backgroundColor = UIColor.secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true
        
        // Add margin around content view
        contentView.frame = contentView.frame.inset(by: UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0))
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Add margin around content view
        contentView.frame = contentView.frame.inset(by: UIEdgeInsets(top: 4, left: 16, bottom: 4, right: 16))
        contentView.layer.cornerRadius = 8
    }
    
    // MARK: - Helper Methods
    
    private func formatTimestamp(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "Just now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
    
    private func getSeverityColor(for crashReason: String) -> UIColor {
        switch crashReason.uppercased() {
        case let reason where reason.contains("EXC_BAD_ACCESS"):
            return .systemRed
        case let reason where reason.contains("SIGABRT"):
            return .systemOrange
        case let reason where reason.contains("EXC_BREAKPOINT"):
            return .systemYellow
        case let reason where reason.contains("SIGSEGV"):
            return .systemRed
        default:
            return .systemBlue
        }
    }
}
