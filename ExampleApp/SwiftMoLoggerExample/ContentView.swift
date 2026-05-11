import SwiftUI
import SwiftMoLogger
import SwiftMoLoggerUI

struct ContentView: View {
    @StateObject private var viewModel = LoggingDemoViewModel()

    var body: some View {
        TabView {
            NavigationStack { DemoTab(viewModel: viewModel) }
                .tabItem { Label("Demo", systemImage: "wand.and.stars") }

            NavigationStack { LogConsoleView() }
                .tabItem { Label("Console", systemImage: "text.alignleft") }

            NavigationStack { DiagnosticsHubView() }
                .tabItem { Label("Hub", systemImage: "scope") }

            NavigationStack { NetworkTab(viewModel: viewModel) }
                .tabItem { Label("Network", systemImage: "network") }

            NavigationStack { DiagnosticsTab(viewModel: viewModel) }
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }

            NavigationStack { AboutTab() }
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }
}

// MARK: - Demo tab — core API surface

private struct DemoTab: View {
    @ObservedObject var viewModel: LoggingDemoViewModel

    var body: some View {
        Form {
            Section {
                Text("Every button here exercises a different piece of the v3 API. Watch the Console or Hub tabs to see logs flow through.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Log levels") {
                Button("trace — verbose entry/exit") {
                    SwiftMoLogger.trace("entering checkout state machine", tag: .Business.workflow)
                }
                Button("debug — DEBUG-only") {
                    SwiftMoLogger.debug("memo-cache miss", tag: .Data.cache)
                }
                Button("info — happy path") {
                    SwiftMoLogger.info("user opened catalogue", tag: .UI.navigation)
                }
                Button("notice — heads-up") {
                    SwiftMoLogger.notice("falling back to cached avatar", tag: .Data.cache)
                }
                Button("warn — slow query") {
                    SwiftMoLogger.warn("query took longer than 200ms", tag: .Data.database, metadata: [
                        "query_id": .string("qry_\(Int.random(in: 1000...9999))"),
                        "duration_ms": .double(234.5)
                    ])
                }
                Button("error — payment failed") {
                    SwiftMoLogger.error("payment declined", tag: .Network.api, metadata: [
                        "order_id": .string("ord_\(Int.random(in: 10_000...99_999))"),
                        "amount": .double(49.99)
                    ])
                }
                Button("error(Error) — thrown value") {
                    struct DemoError: LocalizedError { var errorDescription: String? { "Network unreachable" } }
                    SwiftMoLogger.error(DemoError(), tag: .Network.api)
                }
                Button("critical / fault") {
                    SwiftMoLogger.critical("database integrity violated", tag: .Data.coredata)
                    SwiftMoLogger.fault("watchdog timeout", tag: .System.performance)
                }
            }

            Section("Breadcrumbs") {
                Button("Record user-action breadcrumb") {
                    SwiftMoLogger.breadcrumb("tapped Buy", category: .userAction, metadata: [
                        "sku": .string("ABC-\(Int.random(in: 1...9))")
                    ])
                }
                Button("Record navigation breadcrumb") {
                    SwiftMoLogger.breadcrumb("→ /checkout", category: .navigation)
                }
                LabeledContent("Crumbs in store") {
                    Text("\(viewModel.breadcrumbCount)").monospacedDigit()
                }
            }

            Section("Performance — signposts + macros") {
                Button("LogSignpost.measure — 100 ms span") {
                    LogSignpost.measure("synthetic.work") {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
                Button("Five nested spans") {
                    LogSignpost.measure("outer") {
                        for _ in 0..<5 {
                            LogSignpost.measure("inner") {
                                Thread.sleep(forTimeInterval: 0.01)
                            }
                        }
                    }
                }
                Button("#measure macro") {
                    SugarShowcase.runMeasureMacro()
                }
                Button("#log macro") {
                    SugarShowcase.runLogMacro()
                }
                Button("@AutoLog actor — call method") {
                    Task { try? await SugarShowcase.runAutoLog() }
                }
            }

            Section("Redaction (engine 0)") {
                Button("Log a fake card + token") {
                    SwiftMoLogger.warn(
                        "checkout sent card 4242 4242 4242 4242 with token Bearer abc.def.xyz123, email user@example.com",
                        tag: .Security.security
                    )
                }
                Text("All three values should appear as [REDACTED] in the Console / Hub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ambient context + tracing") {
                Button("withContext { … }") {
                    SwiftMoLogger.withContext(["request_id": .string("req_\(UUID().uuidString.prefix(8))")]) {
                        SwiftMoLogger.info("inside request scope — context auto-attached", tag: .Network.api)
                    }
                }
                Button("withTrace { … } (W3C traceparent)") {
                    SwiftMoLogger.withTrace {
                        SwiftMoLogger.info("inside trace — trace/span IDs auto-attached", tag: .Network.api)
                        SwiftMoLogger.info("nested log carries same trace.id", tag: .Network.api)
                    }
                }
            }

            Section("Error grouping") {
                Button("Emit 5 same-shape errors") {
                    for i in 0..<5 {
                        SwiftMoLogger.error("decode failed for id=\(i): missing key 'price'", tag: .Data.parsing)
                    }
                }
                Text("ErrorGroupingEngine collapses these into one fingerprinted group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Engine stats") {
                LabeledContent("Engines") {
                    Text("\(SwiftMoLogger.engineCount)").monospacedDigit()
                }
                LabeledContent("Memory entries") {
                    Text("\(viewModel.memoryCounters.total)").monospacedDigit()
                }
                LabeledContent("Warnings") {
                    Text("\(viewModel.memoryCounters.warnings)")
                        .monospacedDigit()
                        .foregroundColor(.orange)
                }
                LabeledContent("Errors") {
                    Text("\(viewModel.memoryCounters.errors)")
                        .monospacedDigit()
                        .foregroundColor(.red)
                }
                Button("Clear logs + breadcrumbs", role: .destructive) {
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
