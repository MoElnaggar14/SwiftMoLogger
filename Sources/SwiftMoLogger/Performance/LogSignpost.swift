import Foundation
import os.signpost
import os.log

/// Lightweight wrapper around `os_signpost` for Instruments integration.
///
/// Two ergonomics on top of raw `os_signpost`:
/// 1. ``measure(_:tag:file:function:line:column:_:)`` runs a closure between
///    `.begin` and `.end` signposts and also emits a log entry with the
///    elapsed milliseconds, attributed to the caller's source location.
/// 2. ``Interval`` is an explicit RAII object for begin/end pairs that
///    straddle async boundaries.
public enum LogSignpost {
    fileprivate static let signpostLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "SwiftMoLogger",
        category: .pointsOfInterest
    )

    /// Synchronously measure `block` and emit signpost + log events.
    @discardableResult
    public static func measure<T>(
        _ name: StaticString,
        tag: LogTag? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column,
        _ block: () throws -> T
    ) rethrows -> T {
        let span = Span(name: name, tag: tag)
        defer { span.finish(source: SourceLocation(file: file, function: function, line: line, column: column)) }
        return try block()
    }

    /// Asynchronously measure `block`. Use for async work that may span
    /// suspensions.
    @discardableResult
    public static func measureAsync<T>(
        _ name: StaticString,
        tag: LogTag? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let span = Span(name: name, tag: tag)
        defer { span.finish(source: SourceLocation(file: file, function: function, line: line, column: column)) }
        return try await block()
    }

    /// Begin/end pair for spans that cross function boundaries. Always
    /// `end()` it, ideally with `defer`. Ending twice is a no-op.
    public final class Interval: @unchecked Sendable {
        private let span: Span
        private let source: SourceLocation
        private let lock = UnfairLock()
        private var ended = false

        public init(
            name: StaticString,
            tag: LogTag? = nil,
            file: String = #fileID,
            function: String = #function,
            line: Int = #line,
            column: Int = #column
        ) {
            self.span = Span(name: name, tag: tag)
            self.source = SourceLocation(file: file, function: function, line: line, column: column)
        }

        public func end() {
            let alreadyEnded = lock.withLock {
                defer { ended = true }
                return ended
            }
            guard !alreadyEnded else { return }
            span.finish(source: source)
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

/// One begin/end signpost pair. Owns the single implementation of "end a
/// span": the `.end` signpost, the timing log entry and the Hub event.
private struct Span {
    let name: StaticString
    let tag: LogTag?
    let signpostID: OSSignpostID
    let start: DispatchTime
    let startDate: Date

    init(name: StaticString, tag: LogTag?) {
        self.name = name
        self.tag = tag
        self.signpostID = OSSignpostID(log: LogSignpost.signpostLog)
        self.start = DispatchTime.now()
        self.startDate = Date()
        os_signpost(.begin, log: LogSignpost.signpostLog, name: name, signpostID: signpostID)
    }

    func finish(source: SourceLocation) {
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        os_signpost(
            .end,
            log: LogSignpost.signpostLog,
            name: name,
            signpostID: signpostID,
            "elapsed=%{public}.3fms",
            elapsedMS
        )
        let resolvedTag = tag ?? .performance
        SwiftMoLogger.log(
            .notice,
            "⏱ \(name) took \(String(format: "%.3f", elapsedMS))ms",
            tag: resolvedTag,
            metadata: ["elapsed_ms": .double(elapsedMS), "signpost": .string("\(name)")],
            file: source.file,
            function: source.function,
            line: source.line,
            column: source.column
        )
        SignpostEventStore.shared.record(SignpostEvent(
            name: "\(name)",
            startedAt: startDate,
            endedAt: Date(),
            tagDomain: resolvedTag.domain
        ))
    }
}
