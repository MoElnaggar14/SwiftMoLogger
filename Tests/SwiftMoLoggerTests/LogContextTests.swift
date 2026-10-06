import Foundation
import SwiftMoLogger
import Testing

@Suite("Ambient log context")
struct LogContextTests {
    /// `LogMetadataValue` is `ExpressibleByNilLiteral`, so `== nil` would be ambiguous.
    private func isAbsent(_ value: LogMetadataValue?) -> Bool {
        if case .none = value { return true }
        return false
    }

    @Test func asyncScopeCarriesMetadataIntoChildTasks() async {
        let seen = await LogContext.with(["request_id": "req-7"]) {
            await Task { LogContext.current["request_id"] }.value
        }
        #expect(seen == .string("req-7"))
        #expect(isAbsent(LogContext.current["request_id"]))
    }

    @Test func nestedScopesMergeAndUnwind() async {
        await LogContext.with(["a": "1"]) {
            await LogContext.with(["b": "2"]) {
                await Task.yield()
                #expect(LogContext.current["a"] == .string("1"))
                #expect(LogContext.current["b"] == .string("2"))
            }
            #expect(isAbsent(LogContext.current["b"]))
        }
    }

    @Test func traceRunSetsTraceAndContext() async throws {
        let trace = try #require(TraceContext(traceID: "4bf92f3577b34da6a3ce929d0e0e4736", spanID: "00f067aa0ba902b7"))
        let seen = await trace.run {
            await Task.yield()
            return CurrentTrace.current?.traceID
        }
        #expect(seen == "4bf92f3577b34da6a3ce929d0e0e4736")
        #expect(CurrentTrace.current == nil)
    }

    #if compiler(>=6.4)
    /// Swift 6.4 runs the operation on the caller's executor, so a main-actor
    /// caller stays on the main actor inside the scope.
    @MainActor
    @Test func asyncScopeKeepsTheCallersActor() async {
        await LogContext.with(["screen": "checkout"]) {
            await Task.yield()
            MainActor.assertIsolated()
        }
    }
    #endif
}
