import Foundation

#if canImport(MetricKit) && (os(iOS) || os(macOS))
import MetricKit

/// The ``MetricPayloadSource`` that subscribes to `MXMetricManager`.
///
/// It's the default source of ``MetricKitCrashReporter``. It delivers every
/// payload as its `jsonRepresentation()`. It subscribes to diagnostic payloads
/// on iOS and macOS, and to daily metric payloads on iOS (including Mac Catalyst).
public final class MXMetricManagerPayloadSource: NSObject, MetricPayloadSource {
    private let lock = UnfairLock()
    private var handler: (@Sendable ([MetricKitPayload]) -> Void)?
    private var isSubscribed = false

    /// Receives the payload objects before they're converted to JSON, for the
    /// reporter's delegates, which take MetricKit types. Set before `start`.
    var diagnosticObjectsHandler: (([MXDiagnosticPayload]) -> Void)?

    override public init() {
        super.init()
    }

    public func start(delivering handler: @escaping @Sendable ([MetricKitPayload]) -> Void) {
        let shouldSubscribe = lock.withLock { () -> Bool in
            self.handler = handler
            let wasSubscribed = isSubscribed
            isSubscribed = true
            return !wasSubscribed
        }
        if shouldSubscribe {
            MXMetricManager.shared.add(self)
        }
    }

    public func stop() {
        let shouldUnsubscribe = lock.withLock { () -> Bool in
            handler = nil
            let wasSubscribed = isSubscribed
            isSubscribed = false
            return wasSubscribed
        }
        if shouldUnsubscribe {
            MXMetricManager.shared.remove(self)
        }
    }

    private func deliver(_ payloads: [MetricKitPayload]) {
        guard !payloads.isEmpty, let current = lock.withLock({ self.handler }) else { return }
        current(payloads)
    }
}

extension MXMetricManagerPayloadSource: MXMetricManagerSubscriber {
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        diagnosticObjectsHandler?(payloads)
        deliver(payloads.map { MetricKitPayload(kind: .diagnostics, json: $0.jsonRepresentation()) })
    }

    #if os(iOS)
    public func didReceive(_ payloads: [MXMetricPayload]) {
        deliver(payloads.map { MetricKitPayload(kind: .metrics, json: $0.jsonRepresentation()) })
    }
    #endif
}

#endif
