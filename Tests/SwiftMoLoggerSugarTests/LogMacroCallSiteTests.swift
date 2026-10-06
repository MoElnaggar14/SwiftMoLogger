import Foundation
import SwiftMoLoggerSugar
import Testing

/// Compiles real `#log` call sites, so overload resolution between the `String`
/// and `LogMessage` forms of the macro is checked by the compiler on every
/// toolchain CI runs, not just the expansion text.
@Suite("#log call sites")
struct LogMacroCallSiteTests {
    private func makeLogger(minimumLevel: LogLevel = .trace) -> (MoLogger, EngineRegistry, MemoryLogEngine) {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        let memory = MemoryLogEngine(capacity: 100)
        registry.addEngine(memory)
        registry.minimumLevel = minimumLevel
        return (MoLogger(registry: registry), registry, memory)
    }

    @Test func stringFormsAreUnchanged() {
        let (log, _, memory) = makeLogger()
        let text = "from a variable"
        let count = 2
        let flag = true
        #log(log, "literal")
        #log(log, text)
        #log(log, "interpolated \(count)")
        #log(log, flag ? "on" : "off")
        // Typed from context: both macro forms type-check, and the `String` one must win.
        #log(log, { _ = count; return "inline closure" }())
        #log(log, String(describing: count), level: .warning, tag: .api)

        let entries = memory.snapshot()
        #expect(entries.map(\.message) == [
            "literal", "from a variable", "interpolated 2", "on", "inline closure", "2"
        ])
        #expect(entries.last?.level == .warning)
        #expect(entries.last?.tag == .api)
    }

    @Test func privacyInterpolationsAreHidden() {
        let (log, _, memory) = makeLogger()
        let email = "mo@example.com"
        let device = "iPhone"
        let token = "abc123"
        #log(log, "Signed in \(email, privacy: .private) on \(device)")
        #log(log, "Token \(token, privacy: .sensitive)", level: .error, tag: .authentication)
        #log(log, "Opened \(device, privacy: .public)")

        let entries = memory.snapshot()
        #expect(entries.map(\.message) == ["Signed in <private> on iPhone", "Token <sensitive>", "Opened iPhone"])
        #expect(entries[1].level == .error)
        #expect(entries[1].tag == .authentication)
        #expect(entries.allSatisfy { !$0.formatted().contains(email) && !$0.formatted().contains(token) })
    }

    @Test func logMessageValuesAreAccepted() {
        let (log, _, memory) = makeLogger()
        let userID = 42
        let message: LogMessage = "User \(userID, privacy: .private(mask: .hash))"
        #log(log, message, level: .notice)

        #expect(memory.snapshot().last?.message == "User <hash:07ee7e07b4b19223>")
        #expect(memory.snapshot().last?.level == .notice)
    }

    @Test func revealingPrivateValuesWorksThroughTheMacro() {
        let (log, registry, memory) = makeLogger()
        let email = "mo@example.com"
        registry.revealsPrivateValues = true
        #log(log, "Signed in \(email, privacy: .private)")

        #expect(memory.snapshot().last?.message == "Signed in mo@example.com")
    }

    @Test func capturesTheCallSite() {
        let (log, _, memory) = makeLogger()
        let email = "mo@example.com"
        let line = #line + 1
        #log(log, "Signed in \(email, privacy: .private)")

        let source = memory.snapshot().last?.source
        #expect(source?.file == #fileID)
        #expect(source?.line == line)
        #expect(source?.function == #function)
    }

    @Test func filteredCallsNeverBuildTheMessage() {
        let (log, _, memory) = makeLogger(minimumLevel: .error)
        var evaluated = false
        func value() -> String {
            evaluated = true
            return "x"
        }
        #log(log, "Value \(value(), privacy: .private)")
        #log(log, { evaluated = true; return "payload" }())
        #expect(!evaluated)
        #expect(memory.snapshot().isEmpty)

        #log(log, "Value \(value(), privacy: .private)", level: .error)
        #expect(evaluated)
        #expect(memory.snapshot().last?.message == "Value <private>")
    }
}
