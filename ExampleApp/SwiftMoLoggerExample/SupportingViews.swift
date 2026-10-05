import SwiftUI
import SwiftMoLogger
import SwiftMoLoggerSugar
import SwiftMoLoggerNetwork
import SwiftMoLoggerDiagnostics
import SwiftMoLoggerRemote

// MARK: - Network tab

struct NetworkTab: View {
    @ObservedObject var viewModel: LoggingDemoViewModel
    @State private var lastSummary: String = "—"

    var body: some View {
        Form {
            Section {
                Text("The app builds one `URLSession` with a `NetworkLogger(environment:)` delegate and injects it into this screen's view model. Every call below is logged (request + response), leaves breadcrumbs, and feeds a `NetworkEvent` into the Hub's waterfall view. There is no global hook: instrument any session by passing the logger as its delegate, or per request via `URLSession.shared.data(for:delegate:)`.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Make requests") {
                Button("GET https://httpbin.org/get") {
                    Task { lastSummary = await viewModel.fetch(URL(string: "https://httpbin.org/get")!) }
                }
                Button("GET 404 — https://httpbin.org/status/404") {
                    Task { lastSummary = await viewModel.fetch(URL(string: "https://httpbin.org/status/404")!) }
                }
                Button("GET 500 — https://httpbin.org/status/500") {
                    Task { lastSummary = await viewModel.fetch(URL(string: "https://httpbin.org/status/500")!) }
                }
                Button("Inside TraceContext.run { } — distributed tracing") {
                    Task {
                        lastSummary = await TraceContext.generate().run {
                            await viewModel.fetch(URL(string: "https://httpbin.org/headers")!)
                        }
                    }
                }
                LabeledContent("Last result") {
                    Text(lastSummary).font(.caption).monospaced()
                }
            }

            Section("Sensitive header redaction") {
                Text("`NetworkLogger` scrubs `Authorization`, `Cookie`, `X-API-Key`, and other known-sensitive headers before they are logged. Pass `sensitiveHeaders:` to `NetworkLogger(logger:events:breadcrumbs:sensitiveHeaders:)` to extend `NetworkLogger.defaultSensitiveHeaders`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Network")
    }
}

// MARK: - Diagnostics tab

struct DiagnosticsTab: View {
    @ObservedObject var viewModel: LoggingDemoViewModel
    let logger: MoLogger
    @State private var bugReportURL: URL?
    @State private var liveSinkRunning = false

    var body: some View {
        Form {
            Section("App vitals") {
                if let sample = viewModel.lastVitals {
                    LabeledContent("Memory") {
                        Text(String(format: "%.1f MB", Double(sample.memoryUsedBytes) / 1_048_576))
                            .monospacedDigit()
                    }
                    LabeledContent("CPU") {
                        Text(String(format: "%.1f %%", sample.cpuUsagePercent)).monospacedDigit()
                    }
                    LabeledContent("FPS") {
                        Text(String(format: "%.0f", sample.fps)).monospacedDigit()
                    }
                    LabeledContent("Thermal") {
                        Text(sample.thermalState).monospacedDigit()
                    }
                } else {
                    Text("Sampling once every 5 s — wait a moment…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Flight recorder (rolling 2-min black box)") {
                Text("Active. The recorder captures entries, breadcrumbs, network events, signposts, and vitals into `Library/Caches/SwiftMoLogger/flight-recorder.json` every 2 seconds — so even an immediate crash can be reconstructed on next launch via `recorder.crashedSession`.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Previous run") {
                    if let count = viewModel.recoveredEntryCount {
                        Text("crashed — \(count) entries recovered")
                            .foregroundColor(.red)
                    } else {
                        Text("clean shutdown")
                    }
                }
            }

            Section("Bug report bundle") {
                Button("Generate a bug-report folder") {
                    do {
                        let report = try viewModel.bugReporter.generate(extras: [
                            "trigger": .string("manual"),
                            "screen": .string("Diagnostics")
                        ])
                        bugReportURL = report.directory
                    } catch {
                        logger.error(error, tag: .System.internal)
                    }
                }
                if let url = bugReportURL {
                    Text("Wrote: \(url.lastPathComponent)").font(.caption).monospaced()
                    ShareLink("Share bundle", item: url)
                }
            }

            Section("LiveSink (Bonjour log tail)") {
                Toggle("Advertise _swiftmologger._tcp", isOn: $liveSinkRunning)
                    .onChange(of: liveSinkRunning) { newValue in
                        if newValue { viewModel.startLiveSink() } else { viewModel.stopLiveSink() }
                    }
                Text("DEBUG-only feature — opens a local port and streams JSONL log lines to the `swiftmologger-inspector` CLI on the same network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Remote shippers (mocks)") {
                Text("Production wiring:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("""
                if let sentry = SentryLogEngine(dsn: dsn) { logging.registry.addEngine(sentry) }
                logging.registry.addEngine(DatadogLogEngine(apiKey: key, service: \"app\"))
                logging.registry.addEngine(LokiLogEngine(endpoint: url))
                """)
                .font(.system(.caption, design: .monospaced))
            }

            Section("MetricKit crash + hang capture") {
                Text("Create `MetricKitCrashReporter(logger: logging.logger)` at your composition root, keep it alive, and call `startMonitoring()` to mirror MetricKit crash and hang payloads through that logger automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Diagnostics")
    }
}

// MARK: - About tab

struct AboutTab: View {
    var body: some View {
        Form {
            Section("SwiftMoLogger v4 — full feature matrix") {
                ForEach(features, id: \.headline) { feature in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.headline).font(.headline)
                        Text(feature.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Products in this showcase") {
                Label("SwiftMoLogger — core API + engines", systemImage: "checkmark.seal")
                Label("SwiftMoLoggerUI — Console + Hub", systemImage: "checkmark.seal")
                Label("SwiftMoLoggerNetwork — URLSession capture", systemImage: "checkmark.seal")
                Label("SwiftMoLoggerDiagnostics — vitals, bug report, LiveSink", systemImage: "checkmark.seal")
                Label("SwiftMoLoggerSugar — macros (#log / #measure / @AutoLog)", systemImage: "checkmark.seal")
                Label("SwiftMoLoggerRemote — Sentry / Datadog / Loki shippers", systemImage: "checkmark.seal")
            }

            Section("Drop into your own app") {
                Text("""
                .package(url: \"https://github.com/MoElnaggar14/SwiftMoLogger.git\", from: \"4.0.0\")
                """)
                .font(.system(.caption, design: .monospaced))
            }
        }
        .navigationTitle("About")
    }

    private var features: [(headline: String, detail: String)] {
        [
            ("Structured LogEntry", "Level, tag, metadata, source location & timestamp — every call materialises a typed record."),
            ("Multi-engine fan-out", "Memory + System + File + Remote + custom engines behind one injectable EngineRegistry."),
            ("Dependency injection", "No singletons: one LogEnvironment at the composition root; inject MoLogger (or a child logger) into each component."),
            ("Per-level sampling", "SamplingLogEngine + RateLimitingLogEngine wrappers keep field-device noise sane."),
            ("Redaction", "Regex PII scrubber on emails, tokens, card numbers — wrap any engine in one call."),
            ("Error grouping", "Identical-shape errors collapse into a fingerprint + count."),
            ("Breadcrumbs", "Sentry-compatible ring buffer for crash context."),
            ("Signposts + macros", "Signposter.measure / makeInterval spans + #measure / #log / @AutoLog macros."),
            ("W3C tracing", "TraceContext.run + URLRequest.addTraceparentHeader() for distributed tracing."),
            ("Diagnostics Hub", "Live SwiftUI view: timeline, network waterfall, flame graph, vitals charts, breadcrumbs."),
            ("Flight recorder", "Rolling 2-min black box for post-crash forensics."),
            ("App vitals", "Periodic memory / CPU / FPS / thermal / battery sampler."),
            ("Bug-report bundler", "One call → folder of logs + breadcrumbs + vitals + device info, ready for ShareLink."),
            ("LiveSink + Inspector CLI", "Bonjour log-tail server for DEBUG builds plus a `swiftmologger-inspector` macOS CLI."),
            ("MetricKit reporter", "Mirror MetricKit crash + hang payloads into the logging pipeline."),
            ("Combine + AsyncStream", "Observe entries via environment.stream.subscribe() or a CombineLogPublisher added to the registry."),
            ("Remote shippers", "Sentry envelopes, Datadog logs API, Grafana Loki push — all batched + retried."),
            ("Testing helpers", "XCTAssertLogged + RecordingLogEngine in SwiftMoLoggerTesting."),
            ("Privacy manifest", "Ships a `PrivacyInfo.xcprivacy` so adopters keep App Store compliance.")
        ]
    }
}

// MARK: - Sugar showcase (#log / #measure / @AutoLog)

/// The macros take their logger / signposter explicitly, so the showcase
/// is built from injected dependencies like everything else.
struct SugarShowcase {
    let logger: MoLogger
    let signposter: Signposter

    func runMeasureMacro() {
        let value = #measure(signposter, "sugar.hash") {
            (0..<5000).reduce(0, +)
        }
        logger.info("computed \(value) via #measure", tag: .Business.calculation)
    }

    func runLogMacro() {
        #log(logger, "hello from #log macro", level: .notice, tag: .Development.debug)
    }

    func runAutoLog() throws {
        let service = CheckoutService(logger: logger)
        try service.purchase(id: "SKU-\(Int.random(in: 100...999))")
    }
}

@AutoLog
final class CheckoutService {
    /// Required by `@AutoLog`: its synthesised `__autoLog()` logs through it.
    let logger: MoLogger

    init(logger: MoLogger) {
        self.logger = logger
    }

    func purchase(id: String) throws {
        __autoLog()
        logger.info("processing \(id)", tag: .Business.workflow)
    }
}
