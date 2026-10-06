import SwiftUI
import SwiftMoLogger
import SwiftMoLoggerUI

@MainActor
struct ContentView: View {
    private let logging: LogEnvironment
    @StateObject private var viewModel: LoggingDemoViewModel
    @StateObject private var hub: HubViewModel

    init(dependencies: AppDependencies) {
        self.logging = dependencies.logging
        _viewModel = StateObject(wrappedValue: LoggingDemoViewModel(dependencies: dependencies))
        _hub = StateObject(wrappedValue: Self.makeHubModel(environment: dependencies.logging))
    }

    var body: some View {
        TabView {
            NavigationStack {
                DemoTab(
                    viewModel: viewModel,
                    logger: logging.logger,
                    signposter: logging.signposter,
                    breadcrumbs: logging.breadcrumbs
                )
            }
            .tabItem { Label("Demo", systemImage: "wand.and.stars") }

            NavigationStack { LogConsoleView(stream: logging.stream) }
                .tabItem { Label("Console", systemImage: "text.alignleft") }

            NavigationStack { DiagnosticsHubView(model: hub) }
                .tabItem { Label("Hub", systemImage: "scope") }

            NavigationStack { NetworkTab(viewModel: viewModel) }
                .tabItem { Label("Network", systemImage: "network") }

            NavigationStack { DiagnosticsTab(viewModel: viewModel, logger: logging.logger) }
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }

            NavigationStack { AboutTab() }
                .tabItem { Label("About", systemImage: "info.circle") }
        }
    }

    /// The Hub keeps its own `MemoryLogEngine` (registered by `HubViewModel`).
    /// Wrap it in `RedactingLogEngine` like every other display engine so the
    /// redaction demo shows `[REDACTED]` in the Hub too.
    private static func makeHubModel(environment: LogEnvironment) -> HubViewModel {
        let hub = HubViewModel(environment: environment)
        environment.registry.replaceEngine(id: hub.memoryEngine.engineID) { engine in
            RedactingLogEngine(wrapping: engine)
        }
        return hub
    }
}

// MARK: - Demo tab — core API surface

private struct DemoTab: View {
    @ObservedObject var viewModel: LoggingDemoViewModel
    let logger: MoLogger
    let signposter: Signposter
    let breadcrumbs: BreadcrumbStore

    private var sugar: SugarShowcase {
        SugarShowcase(logger: logger, signposter: signposter)
    }

    var body: some View {
        Form {
            Section {
                Text("Every button here exercises a different piece of the v4 API through an injected `MoLogger`. Watch the Console or Hub tabs to see logs flow through.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Log levels") {
                Button("trace — verbose entry/exit") {
                    logger.trace("entering checkout state machine", tag: .Business.workflow)
                }
                Button("debug — DEBUG-only") {
                    logger.debug("memo-cache miss", tag: .Data.cache)
                }
                Button("info — happy path") {
                    logger.info("user opened catalogue", tag: .UI.navigation)
                }
                Button("notice — heads-up") {
                    logger.notice("falling back to cached avatar", tag: .Data.cache)
                }
                Button("warning — slow query") {
                    logger.warning("query took longer than 200ms", tag: .Data.database, metadata: [
                        "query_id": .string("qry_\(Int.random(in: 1000...9999))"),
                        "duration_ms": .double(234.5)
                    ])
                }
                Button("error — payment failed") {
                    logger.error("payment declined", tag: .Network.api, metadata: [
                        "order_id": .string("ord_\(Int.random(in: 10_000...99_999))"),
                        "amount": .double(49.99)
                    ])
                }
                Button("error(Error) — thrown value") {
                    struct DemoError: LocalizedError { var errorDescription: String? { "Network unreachable" } }
                    logger.error(DemoError(), tag: .Network.api)
                }
                Button("critical / fault") {
                    logger.critical("database integrity violated", tag: .Data.coredata)
                    logger.fault("watchdog timeout", tag: .System.performance)
                }
            }

            Section("Child loggers") {
                Button("with(tag:) + with(metadata:)") {
                    let checkout = logger
                        .with(tag: .Business.workflow)
                        .with(metadata: ["component": "checkout"])
                    checkout.info("cart validated")
                    checkout.notice("coupon applied", metadata: ["coupon": "SPRING10"])
                }
                Text("A child logger carries a default tag and bound metadata, so components never repeat them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Per-value privacy") {
                Button("privacy: .private / .sensitive") {
                    let email = "mo@example.com"
                    let token = "tok_\(Int.random(in: 10_000...99_999))"
                    let userID = 42
                    logger.info(
                        "signed in \(email, privacy: .private) as \(userID, privacy: .private(mask: .hash))",
                        tag: .Security.authentication
                    )
                    logger.notice("refreshed \(token, privacy: .sensitive)", tag: .Security.authentication)
                }
                Text("Only the marked values are hidden: <private>, <sensitive> or a stable <hash:…>.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Breadcrumbs") {
                Button("Record user-action breadcrumb") {
                    breadcrumbs.record("tapped Buy", category: .userAction, metadata: [
                        "sku": .string("ABC-\(Int.random(in: 1...9))")
                    ])
                }
                Button("Record navigation breadcrumb") {
                    breadcrumbs.record("→ /checkout", category: .navigation)
                }
                LabeledContent("Crumbs in store") {
                    Text("\(viewModel.breadcrumbCount)").monospacedDigit()
                }
            }

            Section("Performance — signposts + macros") {
                Button("signposter.measure — 100 ms span") {
                    signposter.measure("synthetic.work") {
                        Thread.sleep(forTimeInterval: 0.1)
                    }
                }
                Button("Five nested spans") {
                    signposter.measure("outer") {
                        for _ in 0..<5 {
                            signposter.measure("inner") {
                                Thread.sleep(forTimeInterval: 0.01)
                            }
                        }
                    }
                }
                Button("makeInterval — span across calls") {
                    let interval = signposter.makeInterval("manual.interval")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        interval.end()
                    }
                }
                Button("#measure macro") {
                    sugar.runMeasureMacro()
                }
                Button("#log macro") {
                    sugar.runLogMacro()
                }
                Button("@AutoLog class — call method") {
                    try? sugar.runAutoLog()
                }
            }

            Section("Redaction") {
                Button("Log a fake card + token") {
                    logger.warning(
                        "checkout sent card 4242 4242 4242 4242 with token Bearer abc.def.xyz123, email user@example.com",
                        tag: .Security.security
                    )
                }
                Text("All three values should appear as [REDACTED] in the Console / Hub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Ambient context + tracing") {
                Button("LogContext.with { … }") {
                    LogContext.with(["request_id": .string("req_\(UUID().uuidString.prefix(8))")]) {
                        logger.info("inside request scope — context auto-attached", tag: .Network.api)
                    }
                }
                Button("TraceContext.run { … } (W3C traceparent)") {
                    TraceContext.generate().run {
                        logger.info("inside trace — trace/span IDs auto-attached", tag: .Network.api)
                        logger.info("nested log carries same trace.id", tag: .Network.api)
                    }
                }
            }

            Section("Error grouping") {
                Button("Emit 5 same-shape errors") {
                    for i in 0..<5 {
                        logger.error("decode failed for id=\(i, privacy: .public): missing key 'price'", tag: .Data.parsing)
                    }
                }
                Text("ErrorGroupingEngine collapses these into one fingerprinted group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Engine stats") {
                LabeledContent("Engines") {
                    Text("\(viewModel.engineCount)").monospacedDigit()
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
    ContentView(dependencies: AppDependencies())
}
