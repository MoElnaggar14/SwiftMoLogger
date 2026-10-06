import Foundation
@testable import SwiftMoLogger
import Testing

@Suite("Per-value privacy")
struct LogMessageTests {
    private func makeLogger(minimumLevel: LogLevel = .trace) -> (MoLogger, EngineRegistry, MemoryLogEngine) {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        let memory = MemoryLogEngine(capacity: 100)
        registry.addEngine(memory)
        registry.minimumLevel = minimumLevel
        return (MoLogger(registry: registry), registry, memory)
    }

    // MARK: Rendering

    @Test func plainInterpolationsRenderLikeString() {
        let count = 3
        let name: String = "Settings"
        let message: LogMessage = "Opened \(name) \(count) times"
        #expect(message.rendered() == "Opened Settings 3 times")
        #expect(message.rendered(revealingPrivateValues: true) == "Opened Settings 3 times")
        #expect(!message.hasPrivateValues)
        #expect(LogMessage(verbatim: "as is").description == "as is")
    }

    @Test func publicValuesAreShown() {
        let screen = "Checkout"
        let message: LogMessage = "Opened \(screen, privacy: .public)"
        #expect(message.rendered() == "Opened Checkout")
        #expect(!message.hasPrivateValues)
    }

    @Test func privateValuesAreHiddenUnlessRevealed() {
        let email = "mo@example.com"
        let device = "iPhone"
        let message: LogMessage = "Signed in \(email, privacy: .private) on \(device)"
        #expect(message.rendered() == "Signed in <private> on iPhone")
        #expect(message.description == "Signed in <private> on iPhone")
        #expect(message.hasPrivateValues)
        #expect(message.rendered(revealingPrivateValues: true) == "Signed in mo@example.com on iPhone")
    }

    @Test func sensitiveValuesAreNeverRevealed() {
        let token = "abc123"
        let email = "mo@example.com"
        let message: LogMessage = "Token \(token, privacy: .sensitive) for \(email, privacy: .private)"
        #expect(message.rendered() == "Token <sensitive> for <private>")
        #expect(message.rendered(revealingPrivateValues: true) == "Token <sensitive> for mo@example.com")

        let onlySensitive: LogMessage = "Token \(token, privacy: .sensitive)"
        #expect(!onlySensitive.hasPrivateValues)
        #expect(onlySensitive.rendered(revealingPrivateValues: true) == "Token <sensitive>")
    }

    @Test func hashMaskIsStableAndPadded() {
        #expect(LogMessage.stableHash("") == "cbf29ce484222325")
        #expect(LogMessage.stableHash("a") == "af63dc4c8601ec8c")
        #expect(LogMessage.stableHash("42") == "07ee7e07b4b19223")

        let userID = 42
        let first: LogMessage = "User \(userID, privacy: .private(mask: .hash))"
        let second: LogMessage = "Again \(userID, privacy: .sensitive(mask: .hash))"
        #expect(first.rendered() == "User <hash:07ee7e07b4b19223>")
        #expect(first.rendered(revealingPrivateValues: true) == "User 42")
        #expect(second.rendered(revealingPrivateValues: true) == "Again <hash:07ee7e07b4b19223>")
    }

    @Test func nestedMessagesKeepHiddenValuesHidden() {
        let email = "mo@example.com"
        let inner: LogMessage = "user \(email, privacy: .private)"
        let outer: LogMessage = "Signed in: \(inner)."
        #expect(outer.rendered() == "Signed in: user <private>.")
        #expect(outer.rendered(revealingPrivateValues: true) == "Signed in: user mo@example.com.")
    }

    // MARK: Logging

    @Test func loggerRendersHiddenValuesBeforeEnginesSeeThem() {
        let (log, _, memory) = makeLogger()
        let email = "mo@example.com"
        log.info("Signed in \(email, privacy: .private)", tag: .authentication, metadata: ["step": "done"])

        let entry = memory.snapshot().last
        #expect(entry?.message == "Signed in <private>")
        #expect(entry?.level == .info)
        #expect(entry?.tag == .authentication)
        #expect(entry?.metadata["step"] == .string("done"))
        #expect(memory.snapshot().allSatisfy { !$0.formatted().contains(email) })
    }

    @Test func everyLevelAcceptsALogMessage() {
        let (log, _, memory) = makeLogger()
        let secret = "s3cret"
        log.trace("t \(secret, privacy: .private)")
        log.debug("d \(secret, privacy: .private)")
        log.info("i \(secret, privacy: .private)")
        log.notice("n \(secret, privacy: .private)")
        log.warning("w \(secret, privacy: .private)")
        log.error("e \(secret, privacy: .private)")
        log.critical("c \(secret, privacy: .private)")
        log.fault("f \(secret, privacy: .private)")
        log.log(.info, "l \(secret, privacy: .private)")

        let messages = memory.snapshot().map(\.message)
        #expect(messages.allSatisfy { $0.hasSuffix(" <private>") })
        #if DEBUG
        #expect(messages.count == 9)
        #else
        #expect(messages.count == 8)
        #endif
    }

    @Test func registryCanRevealPrivateValues() {
        let (log, registry, memory) = makeLogger()
        let email = "mo@example.com"
        let token = "abc123"
        #expect(!registry.revealsPrivateValues)

        registry.revealsPrivateValues = true
        log.info("Signed in \(email, privacy: .private) with \(token, privacy: .sensitive)")
        #expect(memory.snapshot().last?.message == "Signed in mo@example.com with <sensitive>")

        registry.reset()
        #expect(!registry.revealsPrivateValues)
    }

    @Test func filteredCallsNeverBuildTheMessage() {
        let (log, _, memory) = makeLogger(minimumLevel: .error)
        var evaluated = false
        func value() -> String {
            evaluated = true
            return "x"
        }
        log.info("Value \(value(), privacy: .private)")
        #expect(!evaluated)
        #expect(memory.snapshot().isEmpty)

        log.error("Value \(value(), privacy: .private)")
        #expect(evaluated)
    }

    @Test func stringCallSitesAreUnchanged() {
        let (log, _, memory) = makeLogger()
        let text = "from a variable"
        let count = 2
        log.info(text)
        log.info("literal")
        log.info("interpolated \(count)")
        log.error(CocoaError(.fileNoSuchFile))
        let messages = memory.snapshot().map(\.message)
        #expect(Array(messages.prefix(3)) == ["from a variable", "literal", "interpolated 2"])
        #expect(messages.count == 4)
    }
}
