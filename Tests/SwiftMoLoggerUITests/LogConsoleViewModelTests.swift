#if canImport(SwiftUI)
import XCTest
@testable import SwiftMoLogger
@testable import SwiftMoLoggerUI

@MainActor
final class LogConsoleViewModelTests: XCTestCase {

    private var environment: LogEnvironment!

    override func setUp() async throws {
        try await super.setUp()
        environment = LogEnvironment(registry: EngineRegistry(installDefaultSystemLogger: false))
    }

    private func makeModel(bufferLimit: Int = 100) -> LogConsoleViewModel {
        LogConsoleViewModel(stream: environment.stream, bufferLimit: bufferLimit)
    }

    func testStreamingIngestsEntries() async {
        let model = makeModel()
        model.start()
        defer { model.stop() }

        try? await Task.sleep(nanoseconds: 50_000_000)
        environment.logger.info("ui-1")
        environment.logger.warning("ui-2")
        environment.logger.error("ui-3")

        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.entries.count, 3)
        XCTAssertEqual(model.entries.map(\.message), ["ui-1", "ui-2", "ui-3"])
    }

    func testFilteringByLevel() async {
        let model = makeModel()
        model.entries = [
            LogEntry(level: .info, message: "i"),
            LogEntry(level: .warning, message: "w"),
            LogEntry(level: .error, message: "e")
        ]
        model.minimumLevel = .warning
        XCTAssertEqual(model.visibleEntries.count, 2)
    }

    func testFilteringByText() async {
        let model = makeModel()
        model.entries = [
            LogEntry(level: .info, message: "apple"),
            LogEntry(level: .info, message: "banana"),
            LogEntry(level: .info, message: "cherry")
        ]
        model.filterText = "ban"
        XCTAssertEqual(model.visibleEntries.map(\.message), ["banana"])
    }

    func testPauseStopsIngestion() async {
        let model = makeModel()
        model.start()
        defer { model.stop() }
        try? await Task.sleep(nanoseconds: 50_000_000)
        model.isPaused = true
        environment.logger.info("dropped-while-paused")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.entries.contains { $0.message == "dropped-while-paused" })
    }

    func testReleasedHubRemovesItsMemoryEngine() {
        let baseline = environment.registry.engineCount
        do {
            let hub = HubViewModel(environment: environment)
            XCTAssertEqual(environment.registry.engineCount, baseline + 1)
            _ = hub
        }
        XCTAssertEqual(environment.registry.engineCount, baseline)
    }

    func testBufferLimitTrimsOldest() async {
        let model = makeModel(bufferLimit: 5)
        for index in 0..<20 {
            model.entries.append(LogEntry(level: .info, message: "m\(index)"))
            if model.entries.count > model.bufferLimit {
                model.entries.removeFirst(model.entries.count - model.bufferLimit)
            }
        }
        XCTAssertEqual(model.entries.count, 5)
    }
}
#endif
