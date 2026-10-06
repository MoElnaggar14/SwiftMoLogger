import Foundation
@testable import SwiftMoLogger
import Testing

@Suite("File protection")
struct FileProtectionTests {
    private func temporaryLogURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FileProtectionTests-\(UUID().uuidString)")
            .appendingPathComponent("app.log")
    }

    @Test func defaultKeepsBackgroundLoggingWorking() throws {
        let engine = try FileLogEngine(fileURL: temporaryLogURL())
        #expect(engine.protection == .completeUntilFirstUserAuthentication)
    }

    #if os(macOS)
    @Test func macOSHasNoPerFileProtection() {
        #expect(FileLogEngine.Protection.complete.fileAttributes.isEmpty)
    }
    #else
    @Test func everyClassMapsToItsFileProtectionType() {
        let expected: [(FileLogEngine.Protection, FileProtectionType)] = [
            (.unprotected, .none),
            (.completeUntilFirstUserAuthentication, .completeUntilFirstUserAuthentication),
            (.completeUnlessOpen, .completeUnlessOpen),
            (.complete, .complete)
        ]
        for (protection, type) in expected {
            #expect(protection.fileProtectionType == type)
            #expect(protection.fileAttributes[.protectionKey] as? FileProtectionType == type)
        }
    }
    #endif

    @Test func rotationKeepsWritingWithAStrongerClass() throws {
        let url = temporaryLogURL()
        let engine = try FileLogEngine(
            fileURL: url,
            maxFileSizeBytes: 300,
            maxRotatedFiles: 2,
            protection: .completeUnlessOpen,
            minimumLevel: .trace
        )

        for index in 0..<50 { engine.log(LogEntry(level: .info, message: "line \(index)")) }
        engine.flush()

        let files = engine.allLogFileURLs()
        #expect(files.count == 3, "the active file plus two rotated files")
        let contents = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined()
        #expect(contents.contains("line 49"))
    }

    @Test func reopeningAnExistingFileAppliesTheClass() throws {
        let url = temporaryLogURL()
        _ = try FileLogEngine(fileURL: url, protection: .unprotected)

        let engine = try FileLogEngine(fileURL: url, protection: .completeUnlessOpen)
        engine.log(LogEntry(level: .warning, message: "after reopen"))
        engine.flush()

        #expect(try String(contentsOf: url, encoding: .utf8).contains("after reopen"))
    }
}
