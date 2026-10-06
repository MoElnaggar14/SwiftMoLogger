import Foundation
import SwiftMoLoggerSugar
import Testing

/// Compiles a real `@AutoLog` type, so the synthesised `__autoLog()` call is
/// type-checked against the `MoLogger` overloads on every toolchain CI runs.
@Suite("@AutoLog call sites")
struct AutoLogCallSiteTests {
    @AutoLog
    final class TracedCheckout {
        let logger: MoLogger

        init(logger: MoLogger) {
            self.logger = logger
        }

        func purchase(id: String) {
            __autoLog()
        }
    }

    @Test func logsTheMethodNameAsATraceEntry() {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        let memory = MemoryLogEngine(capacity: 10)
        registry.addEngine(memory)
        registry.minimumLevel = .trace

        TracedCheckout(logger: MoLogger(registry: registry)).purchase(id: "SKU-1")

        let entry = memory.snapshot().last
        #expect(entry?.message == "→ purchase(id:)")
        #expect(entry?.level == .trace)
        #expect(entry?.tag == LogTag.Development.debug)
        #expect(entry?.source.function == "purchase(id:)")
    }
}
