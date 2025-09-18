import SwiftUI
import SwiftMoLogger

struct ContentView: View {
    @StateObject private var viewModel = LoggingDemoViewModel()
    @State private var showingLogViewer = false
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    loggingActionsSection
                    statisticsSection
                    engineStatusSection
                    recentLogsSection
                }
                .padding()
            }
            .navigationTitle("SwiftMoLogger Demo")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button("Settings") {
                        showingSettings = true
                    }
                    
                    Button("View Logs") {
                        showingLogViewer = true
                    }
                }
            }
            .sheet(isPresented: $showingLogViewer) {
                LogViewerSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheet(viewModel: viewModel)
            }
        }
        .onAppear {
            viewModel.startPeriodicUpdates()
        }
        .onDisappear {
            viewModel.stopPeriodicUpdates()
        }
    }
    
    // MARK: - View Components
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            Text("SwiftMoLogger")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Advanced Multi-Engine Logging Framework")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack {
                Label("\(viewModel.engineCount)", systemImage: "engine.combustion")
                Spacer()
                Label("\(viewModel.totalLogs)", systemImage: "doc")
                Spacer() 
                Label("\(viewModel.errorCount)", systemImage: "exclamationmark.triangle")
            }
            .padding(.horizontal)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var loggingActionsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Logging Actions")
                .font(.headline)
                .fontWeight(.semibold)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                LogActionButton(
                    title: "Info Log",
                    icon: "info.circle",
                    color: .blue
                ) {
                    viewModel.logInfo()
                }
                
                LogActionButton(
                    title: "Warning",
                    icon: "exclamationmark.triangle",
                    color: .orange
                ) {
                    viewModel.logWarning()
                }
                
                LogActionButton(
                    title: "Error",
                    icon: "xmark.circle",
                    color: .red
                ) {
                    viewModel.logError()
                }
                
                LogActionButton(
                    title: "Network Test",
                    icon: "network",
                    color: .green
                ) {
                    viewModel.simulateNetworkOperation()
                }
                
                LogActionButton(
                    title: "Performance",
                    icon: "speedometer",
                    color: .purple
                ) {
                    viewModel.simulatePerformanceIssue()
                }
                
                LogActionButton(
                    title: "Background Task",
                    icon: "clock",
                    color: .indigo
                ) {
                    viewModel.simulateBackgroundTask()
                }
            }
        }
    }
    
    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analytics")
                .font(.headline)
                .fontWeight(.semibold)
            
            HStack(spacing: 20) {
                StatCard(
                    title: "Total Logs",
                    value: "\(viewModel.totalLogs)",
                    icon: "doc.text",
                    color: .blue
                )
                
                StatCard(
                    title: "Errors",
                    value: "\(viewModel.errorCount)",
                    icon: "xmark.circle.fill",
                    color: .red
                )
                
                StatCard(
                    title: "Warnings", 
                    value: "\(viewModel.warningCount)",
                    icon: "exclamationmark.triangle.fill",
                    color: .orange
                )
            }
        }
    }
    
    private var engineStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Engines")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 8) {
                EngineStatusRow(
                    name: "System Logger",
                    description: "Console output with emoji indicators",
                    icon: "terminal",
                    isActive: true
                )
                
                #if DEBUG
                EngineStatusRow(
                    name: "Memory Engine",
                    description: "In-memory circular buffer (\(viewModel.memoryLogCount) logs)",
                    icon: "memorychip",
                    isActive: true
                )
                
                EngineStatusRow(
                    name: "Debug Engine",
                    description: "Enhanced console with timestamps",
                    icon: "ladybug",
                    isActive: true
                )
                #endif
                
                EngineStatusRow(
                    name: "File Engine",
                    description: "JSON logs in Documents (\(viewModel.fileSize))",
                    icon: "doc.circle",
                    isActive: true
                )
                
                EngineStatusRow(
                    name: "Analytics Engine",
                    description: "Error tracking and performance monitoring",
                    icon: "chart.bar",
                    isActive: true
                )
            }
        }
    }
    
    private var recentLogsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Logs")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("View All") {
                    showingLogViewer = true
                }
                .font(.caption)
            }
            
            if viewModel.recentLogs.isEmpty {
                Text("No logs available")
                    .foregroundColor(.secondary)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                VStack(spacing: 4) {
                    ForEach(viewModel.recentLogs.prefix(5), id: \.id) { log in
                        LogEntryRow(entry: log)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct LogActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct EngineStatusRow: View {
    let name: String
    let description: String
    let icon: String
    let isActive: Bool
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isActive ? .green : .gray)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Circle()
                .fill(isActive ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct LogEntryRow: View {
    let entry: MemoryLogEngine.LogEntry
    
    var body: some View {
        HStack {
            Circle()
                .fill(levelColor)
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.message)
                    .font(.caption)
                    .lineLimit(2)
                
                Text(formatTimestamp(entry.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(entry.level)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(levelColor.opacity(0.2))
                .foregroundColor(levelColor)
                .cornerRadius(4)
        }
        .padding(.horizontal, 8)
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
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    ContentView()
}