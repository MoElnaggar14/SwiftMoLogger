import Foundation
import SwiftMoLogger
import Testing

@Suite("Per-tag minimum levels")
struct LevelOverridesTests {
    private func makeRegistry(minimumLevel: LogLevel = .info) -> (EngineRegistry, MemoryLogEngine) {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        let memory = MemoryLogEngine(capacity: 100)
        registry.addEngine(memory)
        registry.minimumLevel = minimumLevel
        return (registry, memory)
    }

    // MARK: Matching

    @Test func keyMatchesItsDomainAndChildrenButNotSiblings() {
        let overrides: LevelOverrides = ["data": .trace]
        #expect(overrides.minimumLevel(for: "data", fallback: .info) == .trace)
        #expect(overrides.minimumLevel(for: "data.database", fallback: .info) == .trace)
        #expect(overrides.minimumLevel(for: "database", fallback: .info) == .info)
        #expect(overrides.minimumLevel(for: "datastore", fallback: .info) == .info)
        #expect(overrides.minimumLevel(for: nil, fallback: .info) == .info)
    }

    @Test func mostSpecificKeyWins() {
        let overrides: LevelOverrides = ["data": .error, "data.database": .trace]
        #expect(overrides.minimumLevel(for: "data.database", fallback: .info) == .trace)
        #expect(overrides.minimumLevel(for: "data.database.migrations", fallback: .info) == .trace)
        #expect(overrides.minimumLevel(for: "data.cache", fallback: .info) == .error)
    }

    @Test func subscriptSetsReplacesAndRemoves() {
        var overrides = LevelOverrides()
        overrides["network"] = .trace
        overrides["network"] = .warning
        #expect(overrides.levels == ["network": .warning])
        overrides["network"] = nil
        #expect(overrides.isEmpty)
        overrides[""] = .trace
        #expect(overrides.isEmpty, "an empty domain would match nothing useful")
    }

    @Test func levelNamesParseForRemoteConfig() {
        #expect(LogLevel(name: "TRACE") == .trace)
        #expect(LogLevel(name: "warn") == .warning)
        #expect(LogLevel(name: "Warning") == .warning)
        #expect(LogLevel(name: "verbose") == nil)
        for level in LogLevel.allCases {
            #expect(LogLevel(name: level.description) == level, "names round-trip from description")
        }
    }

    // MARK: Registry

    @Test func overrideLowersTheThresholdForOneArea() {
        let (registry, memory) = makeRegistry(minimumLevel: .info)
        registry.setMinimumLevel(.trace, for: .Data.database)
        let logger = MoLogger(registry: registry)

        logger.trace("query plan", tag: .Data.database)
        logger.trace("cache miss", tag: .Data.cache)
        logger.trace("untagged")

        #expect(memory.snapshot().map(\.message) == ["query plan"])
    }

    @Test func overrideRaisesTheThresholdForANoisyArea() {
        let (registry, memory) = makeRegistry(minimumLevel: .trace)
        registry.levelOverrides = ["thirdparty": .error]
        let logger = MoLogger(registry: registry)

        logger.warning("sdk chatter", tag: .ThirdParty.analytics)
        logger.error("sdk failed", tag: .ThirdParty.analytics)
        logger.trace("app detail", tag: .UI.navigation)

        #expect(memory.snapshot().map(\.message) == ["sdk failed", "app detail"])
    }

    @Test func filteredCallsNeverBuildTheMessage() {
        let (registry, _) = makeRegistry(minimumLevel: .trace)
        registry.setMinimumLevel(.error, for: .Network.api)
        let logger = MoLogger(registry: registry, tag: .Network.api)
        var evaluated = false

        logger.info({ evaluated = true; return "payload" }())

        #expect(!evaluated)
    }

    @Test func entriesDispatchedDirectlyRespectOverrides() {
        let (registry, memory) = makeRegistry(minimumLevel: .info)
        registry.setMinimumLevel(.trace, for: .Network.network)

        registry.dispatch(LogEntry(level: .trace, message: "kept", tag: .Network.api))
        registry.dispatch(LogEntry(level: .trace, message: "dropped", tag: .Data.cache))

        #expect(memory.snapshot().map(\.message) == ["kept"])
    }

    @Test func removingAnOverrideInheritsAgain() {
        let (registry, memory) = makeRegistry(minimumLevel: .info)
        registry.setMinimumLevel(.trace, for: .Data.database)
        registry.removeMinimumLevel(for: .Data.database)

        MoLogger(registry: registry).trace("dropped", tag: .Data.database)

        #expect(memory.snapshot().isEmpty)
        #expect(registry.levelOverrides.isEmpty)
    }

    @Test func resetClearsOverrides() {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        registry.setMinimumLevel(.trace, for: .Data.database)
        registry.reset()
        #expect(registry.levelOverrides.isEmpty)
    }

    @Test func perEngineLevelsStillApply() {
        let registry = EngineRegistry(installDefaultSystemLogger: false)
        let errorsOnly = MemoryLogEngine(capacity: 10, minimumLevel: .error)
        registry.addEngine(errorsOnly)
        registry.minimumLevel = .info
        registry.setMinimumLevel(.trace, for: .Data.database)

        MoLogger(registry: registry).trace("verbose", tag: .Data.database)

        #expect(errorsOnly.snapshot().isEmpty)
    }

    @Test func changingOverridesWhileLoggingIsSafe() async {
        let (registry, memory) = makeRegistry(minimumLevel: .info)
        let logger = MoLogger(registry: registry, tag: .Data.database)

        await withTaskGroup(of: Void.self) { group in
            for writer in 0..<4 {
                group.addTask {
                    for index in 0..<500 { logger.error("w\(writer)-\(index)") }
                }
            }
            group.addTask {
                for index in 0..<500 {
                    if index.isMultiple(of: 2) {
                        registry.setMinimumLevel(.trace, for: .Data.database)
                    } else {
                        registry.removeMinimumLevel(for: .Data.database)
                    }
                }
            }
        }

        #expect(memory.snapshot().count == 100, "errors pass either way; the ring buffer holds 100")
    }
}
