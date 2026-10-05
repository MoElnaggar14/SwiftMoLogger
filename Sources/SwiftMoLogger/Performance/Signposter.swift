import Foundation
import os.signpost
import os.log

/// Measures spans of work: emits `os_signpost` intervals for Instruments, a
/// timing log entry through its ``MoLogger``, and (optionally) a
/// ``SignpostEvent`` for the Diagnostics Hub's flame graph.
///
/// Get one from your ``LogEnvironment``, or build it from its parts:
///
/// ```swift
/// let signposter = environment.signposter
/// let users = try signposter.measure("loadUsers") { try store.loadUsers() }
/// ```
public struct Signposter: @unchecked Sendable {
    // OSLog is immutable and documented as thread-safe.
    private let osLog: OSLog
    private let logger: MoLogger
    private let store: SignpostEventStore?

    /// - Parameters:
    ///   - logger: Receives one `.notice` entry per finished span.
    ///   - store: Records spans for the Diagnostics Hub. `nil` to skip.
    ///   - subsystem: The signpost subsystem. Defaults to the bundle identifier.
    public init(logger: MoLogger, store: SignpostEventStore? = nil, subsystem: String? = nil) {
        self.osLog = OSLog(
            subsystem: subsystem ?? Bundle.main.bundleIdentifier ?? "SwiftMoLogger",
            category: .pointsOfInterest
        )
        self.logger = logger
        self.store = store
    }

    /// Synchronously measures `block`.
    @discardableResult
    public func measure<T>(
        _ name: StaticString,
        tag: LogTag? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column,
        _ block: () throws -> T
    ) rethrows -> T {
        let span = begin(name, tag: tag)
        defer { finish(span, source: SourceLocation(file: file, function: function, line: line, column: column)) }
        return try block()
    }

    /// Measures async work that may span suspensions.
    @discardableResult
    public func measureAsync<T>(
        _ name: StaticString,
        tag: LogTag? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column,
        _ block: () async throws -> T
    ) async rethrows -> T {
        let span = begin(name, tag: tag)
        defer { finish(span, source: SourceLocation(file: file, function: function, line: line, column: column)) }
        return try await block()
    }

    /// Starts an interval that ends when ``Interval/end()`` is called (or the
    /// interval is deallocated). Use for spans that cross function boundaries.
    public func makeInterval(
        _ name: StaticString,
        tag: LogTag? = nil,
        file: String = #fileID,
        function: String = #function,
        line: Int = #line,
        column: Int = #column
    ) -> Interval {
        Interval(
            signposter: self,
            span: begin(name, tag: tag),
            source: SourceLocation(file: file, function: function, line: line, column: column)
        )
    }

    /// Emits a one-shot point of interest on the Instruments timeline.
    public func event(_ name: StaticString, message: String = "") {
        if message.isEmpty {
            os_signpost(.event, log: osLog, name: name)
        } else {
            os_signpost(.event, log: osLog, name: name, "%{public}@", message)
        }
    }

    /// A begin/end pair. Ending twice is a no-op.
    public final class Interval: @unchecked Sendable {
        private let signposter: Signposter
        private let span: Span
        private let source: SourceLocation
        private let lock = UnfairLock()
        private var ended = false

        fileprivate init(signposter: Signposter, span: Span, source: SourceLocation) {
            self.signposter = signposter
            self.span = span
            self.source = source
        }

        public func end() {
            let alreadyEnded = lock.withLock {
                defer { ended = true }
                return ended
            }
            guard !alreadyEnded else { return }
            signposter.finish(span, source: source)
        }

        deinit { end() }
    }

    // MARK: - Span

    fileprivate struct Span {
        let name: StaticString
        let tag: LogTag?
        let signpostID: OSSignpostID
        let start: DispatchTime
        let startDate: Date
    }

    private func begin(_ name: StaticString, tag: LogTag?) -> Span {
        let span = Span(
            name: name,
            tag: tag,
            signpostID: OSSignpostID(log: osLog),
            start: DispatchTime.now(),
            startDate: Date()
        )
        os_signpost(.begin, log: osLog, name: name, signpostID: span.signpostID)
        return span
    }

    /// The single implementation of "end a span".
    fileprivate func finish(_ span: Span, source: SourceLocation) {
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - span.start.uptimeNanoseconds) / 1_000_000
        os_signpost(
            .end,
            log: osLog,
            name: span.name,
            signpostID: span.signpostID,
            "elapsed=%{public}.3fms",
            elapsedMS
        )
        let tag = span.tag ?? .performance
        logger.log(
            .notice,
            "⏱ \(span.name) took \(String(format: "%.3f", elapsedMS))ms",
            tag: tag,
            metadata: ["elapsed_ms": .double(elapsedMS), "signpost": .string("\(span.name)")],
            file: source.file,
            function: source.function,
            line: source.line,
            column: source.column
        )
        store?.record(SignpostEvent(
            name: "\(span.name)",
            startedAt: span.startDate,
            endedAt: Date(),
            tagDomain: tag.domain
        ))
    }
}
