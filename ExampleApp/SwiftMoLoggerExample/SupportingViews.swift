import SwiftUI
import SwiftMoLogger

// MARK: - Log Viewer Sheet

struct LogViewerSheet: View {
    @ObservedObject var viewModel: LoggingDemoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: LogLevel = .all
    @State private var searchText = ""
    
    enum LogLevel: String, CaseIterable {
        case all = "All"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        
        var color: Color {
            switch self {
            case .all: return .primary
            case .info: return .blue
            case .warn: return .orange
            case .error: return .red
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Filter Controls
                VStack(spacing: 12) {
                    HStack {
                        Text("Filter by Level:")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Spacer()
                        
                        Picker("Log Level", selection: $selectedLevel) {
                            ForEach(LogLevel.allCases, id: \.self) { level in
                                Text(level.rawValue)
                                    .foregroundColor(level.color)
                                    .tag(level)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    SearchBar(text: $searchText)
                }
                .padding()
                .background(Color(.systemGray6))
                
                // Log List
                List {
                    ForEach(filteredLogs, id: \.id) { log in
                        LogDetailRow(entry: log)
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Log Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        viewModel.clearMemoryLogs()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    private var filteredLogs: [MemoryLogEngine.LogEntry] {
        let allLogs = viewModel.recentLogs
        
        let levelFiltered = selectedLevel == .all ? 
            allLogs : 
            allLogs.filter { $0.level == selectedLevel.rawValue }
        
        if searchText.isEmpty {
            return levelFiltered
        } else {
            return levelFiltered.filter { 
                $0.message.lowercased().contains(searchText.lowercased())
            }
        }
    }
}

struct LogDetailRow: View {
    let entry: MemoryLogEngine.LogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(levelColor)
                    .frame(width: 10, height: 10)
                
                Text(entry.level)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(levelColor.opacity(0.2))
                    .foregroundColor(levelColor)
                    .cornerRadius(4)
                
                Spacer()
                
                Text(formatTimestamp(entry.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(entry.message)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
    
    private var levelColor: Color {
        switch entry.level {
        case "ERROR": return .red
        case "WARN": return .orange
        case "INFO": return .blue
        default: return .gray
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search logs...", text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            
            if !text.isEmpty {
                Button("Clear") {
                    text = ""
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @ObservedObject var viewModel: LoggingDemoViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingFileViewer = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Engine Status") {
                    HStack {
                        Image(systemName: "engine.combustion")
                            .foregroundColor(.blue)
                        Text("Active Engines")
                        Spacer()
                        Text("\(viewModel.engineCount)")
                            .fontWeight(.semibold)
                    }
                }
                
                Section("Statistics") {
                    StatisticRow(
                        title: "Total Logs",
                        value: "\(viewModel.totalLogs)",
                        icon: "doc.text",
                        color: .blue
                    )
                    
                    StatisticRow(
                        title: "Errors",
                        value: "\(viewModel.errorCount)",
                        icon: "xmark.circle",
                        color: .red
                    )
                    
                    StatisticRow(
                        title: "Warnings",
                        value: "\(viewModel.warningCount)",
                        icon: "exclamationmark.triangle",
                        color: .orange
                    )
                    
                    StatisticRow(
                        title: "Memory Logs",
                        value: "\(viewModel.memoryLogCount)",
                        icon: "memorychip",
                        color: .purple
                    )
                }
                
                Section("File Logging") {
                    HStack {
                        Image(systemName: "doc.circle")
                            .foregroundColor(.green)
                        Text("Log File Size")
                        Spacer()
                        Text(viewModel.fileSize)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("View Log File") {
                        showingFileViewer = true
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Actions") {
                    Button("Clear Memory Logs") {
                        viewModel.clearMemoryLogs()
                    }
                    .foregroundColor(.orange)
                    
                    Button("Reset Analytics") {
                        viewModel.resetAnalytics()
                    }
                    .foregroundColor(.purple)
                    
                    Button("Generate Test Logs") {
                        generateTestLogs()
                    }
                    .foregroundColor(.blue)
                }
                
                Section("Demo Services") {
                    Button("Test Network Service") {
                        testNetworkService()
                    }
                    
                    Button("Test Database Service") {
                        testDatabaseService()
                    }
                }
                
                Section("About") {
                    HStack {
                        Text("SwiftMoLogger Version")
                        Spacer()
                        Text("2.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Created by")
                        Spacer()
                        Text("Mohammed Elnaggar")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingFileViewer) {
            if let fileURL = viewModel.getLogFileURL() {
                DocumentViewer(url: fileURL)
            } else {
                Text("Log file not available")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func generateTestLogs() {
        // Generate a variety of test logs
        SwiftMoLogger.info("🧪 Generating test logs...", tag: .debug)
        
        for i in 1...10 {
            DispatchQueue.global().asyncAfter(deadline: .now() + Double(i) * 0.1) {
                switch i % 3 {
                case 0:
                    SwiftMoLogger.info("📊 Test info log #\(i)", tag: .testing)
                case 1:
                    SwiftMoLogger.warn("⚠️ Test warning log #\(i)", tag: .testing)
                default:
                    SwiftMoLogger.error("❌ Test error log #\(i)", tag: .testing)
                }
            }
        }
    }
    
    private func testNetworkService() {
        let service = NetworkService()
        service.fetchUserData()
        service.uploadAnalytics()
    }
    
    private func testDatabaseService() {
        let service = DatabaseService()
        service.saveUserSettings()
        service.performMaintenance()
    }
}

struct StatisticRow: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(title)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
    }
}

// MARK: - Document Viewer

struct DocumentViewer: View {
    let url: URL
    @State private var fileContent: String = ""
    @State private var isLoading: Bool = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading log file...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(fileContent)
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                    }
                }
            }
            .navigationTitle("Log File")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if #available(iOS 16.0, *) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    } else {
                        Button(action: {
                            // Fallback for iOS 15 - show activity view
                            showShareSheet(for: url)
                        }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .onAppear {
            loadFileContent()
        }
    }
    
    private func showShareSheet(for url: URL) {
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityViewController, animated: true)
        }
    }
    
    private func loadFileContent() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let lines = content.components(separatedBy: .newlines)
                
                // Show last 100 lines to avoid memory issues with large files
                let displayLines = Array(lines.suffix(100))
                let displayContent = displayLines.joined(separator: "\n")
                
                DispatchQueue.main.async {
                    self.fileContent = displayContent.isEmpty ? "No log entries found" : displayContent
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.fileContent = "Error loading log file: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Previews

#Preview {
    LogViewerSheet(viewModel: LoggingDemoViewModel())
}

#Preview {
    SettingsSheet(viewModel: LoggingDemoViewModel())
}
