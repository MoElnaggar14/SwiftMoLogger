import UIKit
import SwiftMoLogger

class CrashReportsViewController: UIViewController {
    
    // MARK: - UI Components
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)
    private let emptyStateView = UIView()
    private let emptyStateLabel = UILabel()
    private let refreshControl = UIRefreshControl()
    
    // MARK: - Data
    private var crashReports: [CrashReport] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCrashReports()
        
        SwiftMoLogger.info(message: "CrashReportsViewController loaded", tag: LogTag.UserInterface.ui)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        loadCrashReports() // Refresh data when view appears
    }
    
    // MARK: - UI Setup
    
    private func setupUI() {
        title = "Crash Reports"
        view.backgroundColor = UIColor.systemGroupedBackground
        
        setupNavigationBar()
        setupTableView()
        setupEmptyState()
    }
    
    private func setupNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        
        // Clear Cache Button
        let clearButton = UIBarButtonItem(
            title: "Clear Cache",
            style: .plain,
            target: self,
            action: #selector(clearCacheButtonTapped)
        )
        clearButton.tintColor = .systemRed
        
        // Add Sample Report Button (for demo)
        let addButton = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addSampleReportTapped)
        )
        
        navigationItem.rightBarButtonItems = [clearButton, addButton]
        
        // Close button if presented modally
        if navigationController?.viewControllers.first == self {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: self,
                action: #selector(closeButtonTapped)
            )
        }
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.backgroundColor = .clear
        
        // Register cells
        tableView.register(CrashReportTableViewCell.self, forCellReuseIdentifier: "CrashReportCell")
        
        // Add refresh control
        refreshControl.addTarget(self, action: #selector(refreshData), for: .valueChanged)
        tableView.refreshControl = refreshControl
        
        view.addSubview(tableView)
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    private func setupEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        
        emptyStateLabel.text = "No Crash Reports\n\nCrash reports will appear here when your app experiences crashes."
        emptyStateLabel.textAlignment = .center
        emptyStateLabel.numberOfLines = 0
        emptyStateLabel.font = UIFont.systemFont(ofSize: 16)
        emptyStateLabel.textColor = .secondaryLabel
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        
        emptyStateView.addSubview(emptyStateLabel)
        view.addSubview(emptyStateView)
        
        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            emptyStateView.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
            emptyStateView.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
            
            emptyStateLabel.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            emptyStateLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor),
            emptyStateLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor),
            emptyStateLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }
    
    // MARK: - Data Loading
    
    private func loadCrashReports() {
        crashReports = CrashReportCache.shared.getCachedReports()
        updateUI()
        
        SwiftMoLogger.info(message: "Loaded \(crashReports.count) crash reports", tag: LogTag.System.crash)
    }
    
    private func updateUI() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
            self.emptyStateView.isHidden = !self.crashReports.isEmpty
            self.refreshControl.endRefreshing()
            
            // Update navigation title with count
            self.title = self.crashReports.isEmpty ? "Crash Reports" : "Crash Reports (\(self.crashReports.count))"
        }
    }
    
    // MARK: - Actions
    
    @objc private func clearCacheButtonTapped() {
        let alert = UIAlertController(
            title: "Clear Cache",
            message: "Are you sure you want to clear all cached crash reports? This action cannot be undone.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Clear", style: .destructive) { _ in
            self.clearCache()
        })
        
        present(alert, animated: true)
    }
    
    @objc private func addSampleReportTapped() {
        CrashReportCache.shared.addSampleCrashReport()
        loadCrashReports()
        
        // Show a brief success message
        let alert = UIAlertController(title: "Sample Report Added", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    @objc private func closeButtonTapped() {
        dismiss(animated: true)
    }
    
    @objc private func refreshData() {
        loadCrashReports()
    }
    
    private func clearCache() {
        CrashReportCache.shared.clearCache()
        loadCrashReports()
        
        SwiftMoLogger.info(message: "User cleared crash report cache", tag: LogTag.System.crash)
        
        // Show success message
        let alert = UIAlertController(
            title: "Cache Cleared",
            message: "All crash reports have been removed from cache.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension CrashReportsViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return crashReports.isEmpty ? 0 : 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return crashReports.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "CrashReportCell", for: indexPath) as! CrashReportTableViewCell
        let report = crashReports[indexPath.row]
        cell.configure(with: report)
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let cacheSize = CrashReportCache.shared.getCacheSize()
        return "Cache Size: \(cacheSize)"
    }
}

// MARK: - UITableViewDelegate

extension CrashReportsViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let report = crashReports[indexPath.row]
        let detailVC = CrashReportDetailViewController(crashReport: report)
        navigationController?.pushViewController(detailVC, animated: true)
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Remove from data source
            crashReports.remove(at: indexPath.row)
            
            // Update cache
            CrashReportCache.shared.cacheReports(crashReports)
            
            // Update table view
            tableView.deleteRows(at: [indexPath], with: .fade)
            updateUI()
            
            SwiftMoLogger.info(message: "Deleted crash report at index \(indexPath.row)", tag: LogTag.System.crash)
        }
    }
}