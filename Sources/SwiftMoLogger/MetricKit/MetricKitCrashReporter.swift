import Foundation

#if canImport(MetricKit) && (os(iOS) || os(macOS))
import MetricKit

/// Protocol for receiving crash reports
public protocol CrashReportDelegate: AnyObject, Sendable {
    func didReceiveCrashReport(_ report: [String: Any])
}

/// Protocol for receiving hang reports
public protocol HangReportDelegate: AnyObject, Sendable {
    func didReceiveHangReport(_ diagnostic: MXHangDiagnostic, rawData: [String: Any])
}

/// MetricKit-based reporter for crashes, hangs and daily performance metrics.
///
/// MetricKit collects crashes, hangs, CPU exceptions, and disk-write events
/// outside the app's own process — catching cases that in-process reporters
/// miss (jetsam, watchdog timeouts, app-launch crashes). Diagnostic payloads
/// arrive on the next launch. On iOS it also delivers a daily metric payload:
/// launch and resume times, hang time, peak memory, disk writes and CPU time.
/// ``MetricKitPayloadLogger`` logs both kinds as structured entries.
///
/// Usage:
/// ```swift
/// let reporter = MetricKitCrashReporter(logger: environment.logger)
/// reporter.startMonitoring()
/// ```
///
/// Payloads come from a ``MetricPayloadSource``. By default the reporter reads
/// `MetricManager` on iOS 27 and macOS 27 (``MetricManagerPayloadSource``) and
/// `MXMetricManager` on earlier systems (``MXMetricManagerPayloadSource``); the
/// logged entries are the same. Pass another source to ``init(logger:source:)``
/// to replay recorded payloads.
public final class MetricKitCrashReporter: NSObject {
    private let logger: MoLogger
    private let payloadLogger: MetricKitPayloadLogger
    /// `nil` until ``startMonitoring()`` picks the default source.
    private var source: (any MetricPayloadSource)?
    private var isMonitoring = false

    /// Called for each crash. Only the `MXMetricManager` source (or calling
    /// `didReceive(_:)` directly) provides the MetricKit objects these delegates need,
    /// so with ``init(logger:)``, setting a delegate before ``startMonitoring()``
    /// keeps the reporter on `MXMetricManager` on iOS 27 and macOS 27 too.
    public weak var crashReportDelegate: CrashReportDelegate?
    /// Called for each hang. Only the `MXMetricManager` source (or calling
    /// `didReceive(_:)` directly) provides the MetricKit objects these delegates need,
    /// so with ``init(logger:)``, setting a delegate before ``startMonitoring()``
    /// keeps the reporter on `MXMetricManager` on iOS 27 and macOS 27 too.
    public weak var hangReportDelegate: HangReportDelegate?

    /// Reads payloads from `MetricManager` on iOS 27 and macOS 27, and from
    /// `MXMetricManager` on earlier systems or when a delegate is set.
    ///
    /// The source is chosen when ``startMonitoring()`` is first called.
    ///
    /// - Parameter logger: Receives crash, hang, diagnostic and metric summaries.
    public convenience init(logger: MoLogger) {
        self.init(logger: logger, optionalSource: nil)
    }

    /// Reads payloads from `source`.
    ///
    /// - Parameters:
    ///   - logger: Receives crash, hang, diagnostic and metric summaries.
    ///   - source: Delivers payloads once ``startMonitoring()`` is called.
    public convenience init(logger: MoLogger, source: any MetricPayloadSource) {
        self.init(logger: logger, optionalSource: source)
    }

    private init(logger: MoLogger, optionalSource: (any MetricPayloadSource)?) {
        self.logger = logger
        self.payloadLogger = MetricKitPayloadLogger(logger: logger)
        self.source = optionalSource
        super.init()
    }

    public func startMonitoring() {
        guard !isMonitoring else {
            logger.warning("MetricKit monitoring already active", tag: .crash)
            return
        }
        let payloadLogger = self.payloadLogger
        let source = self.source ?? makeDefaultSource()
        self.source = source
        source.start { payloads in
            payloadLogger.log(payloads)
        }
        isMonitoring = true
        logger.info("MetricKit monitoring started", tag: .crash)
    }

    public func stopMonitoring() {
        guard isMonitoring else {
            logger.warning("MetricKit monitoring not active", tag: .crash)
            return
        }
        source?.stop()
        isMonitoring = false
        logger.info("MetricKit monitoring stopped", tag: .crash)
    }

    /// Force a fatal crash for end-to-end MetricKit pipeline validation.
    /// Now public (was internal in v2 despite being documented as public).
    public func triggerTestCrash() {
        #if DEBUG
        logger.warning("Triggering test crash for validation", tag: .crash)
        fatalError("Test crash for MetricKit validation")
        #else
        logger.warning("Test crashes only available in DEBUG builds", tag: .crash)
        #endif
    }
}

/// The reporter subscribes through its source, so these only run if you add
/// the reporter to `MXMetricManager` yourself or forward payloads to it.
extension MetricKitCrashReporter: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        notifyDelegates(of: payloads)
        payloadLogger.log(payloads.map { MetricKitPayload(kind: .diagnostics, json: $0.jsonRepresentation()) })
    }

    #if os(iOS)
    public func didReceive(_ payloads: [MXMetricPayload]) {
        payloadLogger.log(payloads.map { MetricKitPayload(kind: .metrics, json: $0.jsonRepresentation()) })
    }
    #endif
}

private extension MetricKitCrashReporter {
    func makeDefaultSource() -> any MetricPayloadSource {
        #if compiler(>=6.4)
        if #available(iOS 27, macOS 27, *), crashReportDelegate == nil, hangReportDelegate == nil {
            return MetricManagerPayloadSource()
        }
        #endif
        let source = MXMetricManagerPayloadSource()
        source.diagnosticObjectsHandler = { [weak self] payloads in
            self?.notifyDelegates(of: payloads)
        }
        return source
    }

    func notifyDelegates(of payloads: [MXDiagnosticPayload]) {
        guard crashReportDelegate != nil || hangReportDelegate != nil else { return }
        for payload in payloads {
            for diagnostic in payload.crashDiagnostics ?? [] {
                crashReportDelegate?.didReceiveCrashReport(createDetailedCrashReport(from: diagnostic))
            }
            for diagnostic in payload.hangDiagnostics ?? [] {
                let rawData = stringKeyed(diagnostic.dictionaryRepresentation())
                hangReportDelegate?.didReceiveHangReport(diagnostic, rawData: rawData)
            }
        }
    }

    func stringKeyed(_ dictionary: [AnyHashable: Any]) -> [String: Any] {
        Dictionary(uniqueKeysWithValues: dictionary.compactMap { key, value in
            guard let stringKey = key as? String else { return nil }
            return (stringKey, value)
        })
    }

    func createDetailedCrashReport(from diagnostic: MXCrashDiagnostic) -> [String: Any] {
        var report: [String: Any] = [:]
        report["timestamp"] = ISO8601DateFormatter().string(from: Date())
        report["appVersion"] = diagnostic.applicationVersion
        report["osVersion"] = diagnostic.metaData.osVersion
        report["deviceType"] = diagnostic.metaData.deviceType
        if let exceptionType = diagnostic.exceptionType {
            report["exceptionType"] = exceptionType.intValue
        }
        if let signal = diagnostic.signal {
            report["signal"] = signal.intValue
        }
        if let exceptionCode = diagnostic.exceptionCode {
            report["exceptionCode"] = exceptionCode.intValue
        }
        let callStackData = diagnostic.callStackTree.jsonRepresentation()
        if let callStackString = String(data: callStackData, encoding: .utf8) {
            report["callStack"] = callStackString
        }
        return report
    }
}

#endif
