# SwiftMoLogger feature reference (4.x)

Read only the section you need. Every API takes its dependencies explicitly.

## Contents
- Flight recorder and MetricKit
- Bug reports
- Breadcrumbs
- Tracing (W3C traceparent)
- Task-local context
- Signposts
- Streams and Combine
- Sampling, rate limiting and error grouping
- Custom engines
- swift-log interop
- Macros

## Flight recorder and MetricKit

```swift
let recorder = FlightRecorder(environment: logging, redactor: Redactor())  // 2-min window, flushed every 5 s
recorder.start()

if let session = recorder.crashedSession {          // previous run died in the foreground
    logging.logger.warning("Recovered crashed session: \(session.entries.count) entries")
}

let metricKit = MetricKitCrashReporter(logger: logging.logger)   // iOS / macOS
metricKit.startMonitoring()
```

- The recorder captures logs, breadcrumbs, network events, signposts and vitals into Caches. It writes only when something changed, and flushes when the app goes to the background.
- `crashedSession` is set only after a crash, OOM kill or watchdog kill in the foreground. Going to the background marks the session clean. Keep the recorder alive for the app's lifetime by holding it at the composition root.

## Bug reports

```swift
import SwiftMoLoggerDiagnostics
let memory = MemoryLogEngine(capacity: 500)
logging.registry.addEngine(memory)
let reporter = BugReporter(environment: logging, memoryEngine: memory, vitalsMonitor: vitals, appName: "Shop")
let report = try reporter.generate()      // report.directory → ShareLink / uploader
```

Add `systemLog: SystemLogOptions(window: 600)` to include the app's own unified log (Apple frameworks and SDKs log there, not through SwiftMoLogger) as `system-log.txt`, redacted and capped at 1 MB. Reading it takes a moment, so call `generate()` off the main thread. Tests can pass `SystemLogOptions(source:)` with a fake `SystemLogSource`.

## Breadcrumbs

```swift
let breadcrumbs = logging.breadcrumbs     // BreadcrumbStore: inject it
breadcrumbs.record("user tapped Buy", category: .userAction)
breadcrumbs.record("nav → checkout", category: .navigation)
let crumbs = breadcrumbs.snapshot()       // ring buffer, default 100
```

## Tracing (W3C traceparent)

```swift
try await TraceContext.generate().run {
    logger.info("starting checkout")     // carries trace.id / span.id
    var request = URLRequest(url: chargeURL)
    request.addTraceparentHeader()       // 00-<traceID>-<childSpanID>-01
    _ = try await session.data(for: request)
}
let parsed = TraceContext.parse(traceparent: incomingHeader)   // optional
let ctx = TraceContext(traceID: id, spanID: span)              // optional: validates hex, rejects all-zero IDs
```

## Task-local context

```swift
try await LogContext.with(["request_id": "req-42"]) {
    logger.info("fetching profile")      // includes request_id
    try await api.fetchProfile()
}
```

This is backed by `@TaskLocal`, so concurrent tasks don't see each other's context. Read the current context with `LogContext.current`.

## Signposts

```swift
let signposter = logging.signposter      // inject a Signposter
let users = try signposter.measure("loadUsers", tag: .database) { try repo.all() }
let avatar = try await signposter.measureAsync("uploadAvatar") { try await uploader.send(image) }
let span = signposter.makeInterval("imageDownload"); defer { span.end() }
```

Each measurement emits an os_signpost interval, a log entry with `elapsed_ms`, and a span for the Hub's flame graph.

## Streams and Combine

```swift
Task { for await entry in logging.stream.subscribe() where entry.level >= .error { await report(entry) } }

let combine = CombineLogPublisher()
logging.registry.addEngine(combine)
combine.publisher.filter { $0.level >= .error }.sink { _ in }.store(in: &cancellables)
```

## Sampling, rate limiting and error grouping

```swift
logging.registry.addEngine(SamplingLogEngine(wrapping: fileEngine, strategy: .perLevel(rates: [.trace: 0.01, .debug: 0.1])))
logging.registry.addEngine(RateLimitingLogEngine(wrapping: shipper, permitsPerSecond: 50, burst: 100))
let grouper = ErrorGroupingEngine(wrapping: shipper, fingerprintMinLevel: .warning, emitThreshold: 1)
logging.registry.addEngine(grouper)
```

Decorators compose. A typical remote stack, from the outside in: rate limit → error grouping → redaction → shipper.

For an OpenTelemetry backend (Collector, Grafana, Honeycomb, New Relic), the shipper is `OTLPLogEngine(endpoint: URL(string: "https://…:4318/v1/logs")!, serviceName: "app-ios")`. Logs written inside a `TraceContext` carry its trace and span IDs, so they join the backend's traces.

## Custom engines

```swift
final class AnalyticsEngine: LogEngine {
    func log(_ entry: LogEntry) {
        guard entry.level >= .warning else { return }
        Analytics.track(entry.message, properties: entry.metadata.storage)
    }
}
logging.registry.addEngine(AnalyticsEngine())
```

`log(_:)` runs on the caller's thread, so keep it O(1) and hand slow work to your own queue. Give the engine a stable `engineID` if adding it twice should replace it rather than duplicate it. To ship somewhere custom, use `HTTPLogShipper(configuration: .init(endpoint: url, headers: [...]), body: { entries in try JSONEncoder().encode(entries) })`. It handles batching, retries and the offline buffer.

## swift-log interop

```swift
import SwiftMoLoggerSwiftLog
SwiftMoLogHandler.bootstrap(logger: logging.logger)   // once per process
```

## Macros (SwiftMoLoggerSugar)

```swift
#log(logger, "user signed in", level: .info, tag: .api)
let users = try #measure(signposter, "loadUsers") { try repo.all() }

@AutoLog
final class CheckoutService {
    let logger: MoLogger                // @AutoLog logs through this property
    init(logger: MoLogger) { self.logger = logger }
    func purchase(_ id: String) { __autoLog() }   // trace "→ purchase(_:)"
}
```
