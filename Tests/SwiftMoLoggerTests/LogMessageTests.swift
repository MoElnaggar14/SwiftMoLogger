import Foundation
@testable import SwiftMoLogger
import Testing

@Suite("Private by default")
struct LogMessageTests {
    private func makeLogger(minimumLevel: LogLevel = .trace) -> (MoLogger, EngineRegistry, MemoryLogEngine) {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        let memory = MemoryLogEngine(capacity: 100)
        registry.addEngine(memory)
        registry.minimumLevel = minimumLevel
        return (MoLogger(registry: registry), registry, memory)
    }

    // MARK: Rendering

    @Test func unmarkedValuesArePrivate() {
        let count = 3
        let name: String = "Settings"
        let message: LogMessage = "Opened \(name) \(count) times"
        #expect(message.rendered() == "Opened <private> 3 times")
        #expect(message.rendered(revealingPrivateValues: true) == "Opened Settings 3 times")
        #expect(message.hasPrivateValues)
    }

    @Test func literalTextIsPublic() {
        let plain: LogMessage = "Signed in"
        let multiline: LogMessage = """
        Signed in
        again
        """
        #expect(plain.rendered() == "Signed in")
        #expect(multiline.rendered() == "Signed in\nagain")
        #expect(!plain.hasPrivateValues && !multiline.hasPrivateValues)
        #expect(LogMessage(verbatim: "as is").description == "as is")
    }

    @Test func interpolatedStringLiteralsArePrivate() {
        // `\("…")` interpolates a String: write the text into the literal instead.
        let message: LogMessage = "Opened \("Settings")"
        #expect(message.rendered() == "Opened <private>")
    }

    @Test func everyOtherTypeIsPrivate() {
        let email = "mo@example.com"
        let url = URL(string: "https://example.com/u/42")
        let uuid = UUID()
        let numbers = [1, 2]
        let date = Date(timeIntervalSince1970: 0)
        let values: LogMessage = "\(email) \(url) \(uuid) \(numbers) \(date)"
        #expect(values.rendered() == "<private> <private> <private> <private> <private>")
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

    @Test func callSitesDecideHowAStringIsShown() {
        let (log, _, memory) = makeLogger()
        let text = "from a variable"
        let count = 2
        let flag = true
        log.info("\(text)")
        log.info(LogMessage(verbatim: text))
        log.info("literal")
        log.info("interpolated \(count)")
        log.info(flag ? "on" : "off")
        // Typed from context: the closure's literal becomes a LogMessage.
        log.info({ _ = count; return "closure \(text)" }())
        #expect(memory.snapshot().map(\.message) == [
            "<private>", "from a variable", "literal", "interpolated 2", "on", "closure <private>"
        ])
    }

    @Test func errorsHideTheirDescriptionButNotTheirType() {
        let (log, registry, memory) = makeLogger()
        log.error(CocoaError(.fileNoSuchFile))

        let entry = memory.snapshot().last
        #expect(entry?.message == "<private>")
        #expect(entry?.level == .error)
        #expect(entry?.metadata["error_type"] == .string("CocoaError"))

        registry.revealsPrivateValues = true
        log.error(CocoaError(.fileNoSuchFile))
        #expect(memory.snapshot().last?.message == CocoaError(.fileNoSuchFile).localizedDescription)
    }

    @Test func breadcrumbsFollowTheSameRule() {
        let crumbs = BreadcrumbStore(capacity: 4)
        let query = "mo@example.com"
        let screen = "Search"
        crumbs.record("Searched \(query) on \(screen, privacy: .public)")
        crumbs.record("Results: \(3)")
        #expect(crumbs.snapshot().map(\.message) == ["Searched <private> on Search", "Results: 3"])
    }

    @Test func revealingOnlyWorksInDebugBuilds() {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        registry.revealsPrivateValues = true
        let email = "mo@example.com"
        let message: LogMessage = "Signed in \(email)"
        #if DEBUG
        #expect(registry.revealsPrivateValues)
        #expect(message.rendered(revealingPrivateValues: true) == "Signed in mo@example.com")
        #else
        #expect(!registry.revealsPrivateValues)
        #expect(!message.hasPrivateValues)
        #expect(message.rendered(revealingPrivateValues: true) == "Signed in <private>")
        #endif
    }

    // MARK: LogPublicValue

    private enum CheckoutStep: String, CustomStringConvertible, LogPublicValue {
        case payment
        var description: String { rawValue }
    }

    private func isPublicValue<T: LogPublicValue>(_: T.Type) -> Bool { true }

    @Test func builtInTypesArePublicValues() {
        #expect(isPublicValue(Int.self) && isPublicValue(Int8.self) && isPublicValue(Int16.self))
        #expect(isPublicValue(Int32.self) && isPublicValue(Int64.self) && isPublicValue(UInt.self))
        #expect(isPublicValue(UInt8.self) && isPublicValue(UInt16.self) && isPublicValue(UInt32.self))
        #expect(isPublicValue(UInt64.self) && isPublicValue(Float.self) && isPublicValue(Double.self))
        #expect(isPublicValue(Bool.self) && isPublicValue(StaticString.self))
        #expect(isPublicValue(LogLevel.self) && isPublicValue(LogTag.self))
        #expect(isPublicValue(Int?.self) && isPublicValue(CheckoutStep?.self))
    }

    @Test func publicValuesRenderAsBefore() {
        let count = 3
        let ratio = 0.5
        let small: UInt8 = 7
        let isOK = false
        let name: StaticString = "load"
        let step = CheckoutStep.payment
        let missing: Int? = nil
        let present: Int? = 4
        let numbers: LogMessage = "\(count) \(ratio) \(small) \(isOK) \(missing) \(present)"
        let names: LogMessage = "\(name) \(step) \(LogLevel.error) \(LogTag.api)"
        #expect(numbers.rendered() == "3 0.5 7 false nil Optional(4)")
        #expect(names.rendered() == "load payment \(LogLevel.error) \(LogTag.api)")
        #expect(!numbers.hasPrivateValues && !names.hasPrivateValues)
    }

    @Test func unmarkedValuesCanBeRevealedButSensitiveOnesCannot() {
        let email = "mo@example.com"
        let token = "abc123"
        let message: LogMessage = "Signed in \(email) with \(token, privacy: .sensitive)"
        #expect(message.rendered() == "Signed in <private> with <sensitive>")
        #expect(message.rendered(revealingPrivateValues: true) == "Signed in mo@example.com with <sensitive>")
    }

    @Test func publicValuesCanStillBeMarked() {
        let userID = 42
        let step = CheckoutStep.payment
        let message: LogMessage = "User \(userID, privacy: .private) at \(step, privacy: .sensitive)"
        #expect(message.rendered() == "User <private> at <sensitive>")
        #expect(message.rendered(revealingPrivateValues: true) == "User 42 at <sensitive>")
    }

    @Test func publicValuesAreShownInPlainLiterals() {
        let (log, _, memory) = makeLogger()
        let step = CheckoutStep.payment
        let attempt = 2
        log.info("Step \(step), attempt \(attempt)")
        log.notice("Step \(step, privacy: .public)")
        #expect(memory.snapshot().map(\.message) == ["Step payment, attempt 2", "Step payment"])
    }
}
