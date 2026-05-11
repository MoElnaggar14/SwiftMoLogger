import SwiftUI
import SwiftMoLogger
import SwiftMoLoggerUI

/// Top-level screen with three tabs: a "Demo" surface that drives the
/// logger from buttons, the live `LogConsoleView`, and the
/// `DiagnosticsHubView`. Everything else exists to give them signals.
struct ContentView: View {
    @StateObject private var viewModel = LoggingDemoViewModel()

    var body: some View {
        TabView {
            NavigationStack { DemoView(viewModel: viewModel) }
                .tabItem { Label("Demo", systemImage: "wand.and.stars") }

            NavigationStack { LogConsoleView() }
                .tabItem { Label("Console", systemImage: "text.alignleft") }

            NavigationStack { DiagnosticsHubView() }
                .tabItem { Label("Hub", systemImage: "scope") }
        }
    }
}

private struct DemoView: View {
    @ObservedObject var viewModel: LoggingDemoViewModel

    var body: some View {
        Form {
            Section("Log levels") {
                Button("info — happy path") {
                    SwiftMoLogger.info("user opened catalogue", tag: .UI.navigation)
                }
                Button("warn — slow query") {
                    SwiftMoLogger.warn("query took longer than 200ms", tag: .Data.database, metadata: [
                        "query_id": "qry_\(Int.random(in: 1000...9999))",
                        "duration_ms": 234.5
                    ])
                }
                Button("error — payment failed") {
                    SwiftMoLogger.error("payment declined", tag: .Network.api, metadata: [
                        "order_id": "ord_\(Int.random(in: 10_000...99_999))",
                        "amount": 49.99
                    ])
                }
                Button("debug — DEBUG-only") {
                    SwiftMoLogger.debug("entering checkout state machine")
                }
            }

            Section("Breadcrumbs") {
                Button("Record user-action breadcrumb") {
                    SwiftMoLogger.breadcrumb("tapped Buy", category: .userAction, metadata: [
                        "sku": "ABC-\(Int.random(in: 1...9))"
                    ])
                }
                Button("Record navigation breadcrumb") {
                    SwiftMoLogger.breadcrumb("→ /checkout", category: .navigation)
                }
                LabeledContent("Crumbs in store") {
                    Text("\(viewModel.breadcrumbCount)")
                        .monospacedDigit()
                }
            }

            Section("Performance instrumentation") {
                Button("Measure a 100 ms span") {
                    LogSignpost.measure("synthetic.work") {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
                Button("Run 5 nested spans") {
                    LogSignpost.measure("outer") {
                        for index in 0..<5 {
                            LogSignpost.measure("inner-\(index)") {
                                Thread.sleep(forTimeInterval: 0.01)
                            }
                        }
                    }
                }
            }

            Section("Engine stats") {
                LabeledContent("Engines registered") {
                    Text("\(SwiftMoLogger.engineCount)")
                        .monospacedDigit()
                }
                LabeledContent("Memory entries") {
                    Text("\(viewModel.memoryCounters.total)")
                        .monospacedDigit()
                }
                LabeledContent("Warnings") {
                    Text("\(viewModel.memoryCounters.warnings)")
                        .monospacedDigit()
                }
                LabeledContent("Errors") {
                    Text("\(viewModel.memoryCounters.errors)")
                        .monospacedDigit()
                        .foregroundColor(.red)
                }
                Button("Clear all", role: .destructive) {
                    viewModel.clearAll()
                }
            }
        }
        .navigationTitle("SwiftMoLogger")
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}

#Preview {
    ContentView()
}
