import Foundation
import os.signpost
import os.log

/// Lightweight wrapper around `os_signpost` for Instruments integration.
///
/// Two ergonomics on top of raw `os_signpost`:
/// 1. ``measure(_:tag:_:)`` runs a closure between `.begin` and `.end`
///    signposts and also emits a log entry with the elapsed milliseconds.
/// 2. ``Interval`` is an explicit RAII object for begin/end pairs that
///    straddle async boundaries.
///
/// All signpost work is disabled at compile time when the deployment target
/// predates `os.signpost`, falling back to a plain timed log entry.
public enum LogSignpost {
    private static let signpostLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "SwiftMoLogger",
        category: .pointsOfInterest
    )

    /// Synchronously measure `block` and emit signpost + log events.
    @discardableResult
    public static func measure<T>(
        _ name: StaticString,
        tag: LogTag? = nil,
        _ block: () throws -> T
    ) rethrows -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        let start = DispatchTime.now()
        let startDate = Date()
        os_signpost(.begin, log: signpostLog, name: name, signpostID: signpostID)
        defer {
            let elapsedNS = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            let elapsedMS = Double(elapsedNS) / 1_000_000
            os_signpost(.end, log: signpostLog, name: name, signpostID: signpostID, "elapsed=%{public}.3fms", elapsedMS)
            SwiftMoLogger.log(
                .notice,
                "⏱ \(name) took \(String(format: "%.3f", elapsedMS))ms",
                tag: tag ?? .performance,
                metadata: ["elapsed_ms": .double(elapsedMS), "signpost": .string("\(name)")]
            )
            SignpostEventStore.shared.record(SignpostEvent(
                name: "\(name)",
                startedAt: startDate,
                endedAt: Date(),
                tagDomain: (tag ?? .performance).domain
            ))
        }
        return try block()
    }

    /// Asynchronously measure `block`. Use for async work that may span
    /// suspensions.
    @discardableResult
    public static func measureAsync<T>(
        _ name: StaticString,
        tag: LogTag? = nil,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let signpostID = OSSignpostID(log: signpostLog)
        let start = DispatchTime.now()
        let startDate = Date()
        os_signpost(.begin, log: signpostLog, name: name, signpostID: signpostID)
        defer {
            let elapsedNS = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            let elapsedMS = Double(elapsedNS) / 1_000_000
            os_signpost(.end, log: signpostLog, name: name, signpostID: signpostID, "elapsed=%{public}.3fms", elapsedMS)
            SwiftMoLogger.log(
                .notice,
                "⏱ \(name) took \(String(format: "%.3f", elapsedMS))ms",
                tag: tag ?? .performance,
                metadata: ["elapsed_ms": .double(elapsedMS), "signpost": .string("\(name)")]
            )
            SignpostEventStore.shared.record(SignpostEvent(
                name: "\(name)",
                startedAt: startDate,
                endedAt: Date(),
                tagDomain: (tag ?? .performance).domain
            ))
        }
        return try await block()
    }

    /// Begin/end pair for spans that cross function boundaries. Always
    /// `end()` it, ideally with `defer`.
    public final class Interval: @unchecked Sendable {
        private let name: StaticString
        private let tag: LogTag?
        private let signpostID: OSSignpostID
        private let start: DispatchTime
        private let startDate: Date
        private var ended = false

        public init(name: StaticString, tag: LogTag? = nil) {
            self.name = name
            self.tag = tag
            self.signpostID = OSSignpostID(log: LogSignpost.signpostLog)
            self.start = DispatchTime.now()
            self.startDate = Date()
            os_signpost(.begin, log: LogSignpost.signpostLog, name: name, signpostID: signpostID)
        }

        public func end() {
            guard !ended else { return }
            ended = true
            let elapsedNS = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            let elapsedMS = Double(elapsedNS) / 1_000_000
            os_signpost(.end, log: LogSignpost.signpostLog, name: name, signpostID: signpostID, "elapsed=%{public}.3fms", elapsedMS)
            SwiftMoLogger.log(
                .notice,
                "⏱ \(name) took \(String(format: "%.3f", elapsedMS))ms",
                tag: tag ?? .performance,
                metadata: ["elapsed_ms": .double(elapsedMS), "signpost": .string("\(name)")]
            )
            SignpostEventStore.shared.record(SignpostEvent(
                name: "\(name)",
                startedAt: startDate,
                endedAt: Date(),
                tagDomain: (tag ?? .performance).domain
            ))
        }

        deinit { end() }
    }

    /// Emit a one-shot point-of-interest signpost. Useful for marking
    /// significant moments (user tap, network resume) on the Instruments
    /// timeline.
    public static func event(_ name: StaticString, message: String = "") {
        if message.isEmpty {
            os_signpost(.event, log: signpostLog, name: name)
        } else {
            os_signpost(.event, log: signpostLog, name: name, "%{public}@", message)
        }
    }
}
