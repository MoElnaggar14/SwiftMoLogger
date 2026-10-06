import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import SwiftMoLoggerMacros

final class LogMacroTests: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "log": LogMacro.self,
        "measure": MeasureMacro.self
    ]

    func testLogMacroExpandsWithDefaults() {
        assertMacroExpansion(
            #"#log(logger, "hello")"#,
            expandedSource: #"logger.log(.info, "hello", tag: nil, file: #fileID, function: #function, line: #line)"#,
            macros: macros
        )
    }

    func testLogMacroForwardsLevelAndTag() {
        assertMacroExpansion(
            #"#log(self.log, "oops", level: .error, tag: .api)"#,
            expandedSource: #"self.log.log(.error, "oops", tag: .api, file: #fileID, function: #function, line: #line)"#,
            macros: macros
        )
    }

    func testLogMacroPassesPrivacyInterpolationsThrough() {
        assertMacroExpansion(
            #"#log(logger, "Signed in \(email, privacy: .private) on \(device)", level: .notice)"#,
            expandedSource: """
            logger.log(.notice, "Signed in \\(email, privacy: .private) on \\(device)", tag: nil, \
            file: #fileID, function: #function, line: #line)
            """,
            macros: macros
        )
    }

    func testLogMacroPassesMessageExpressionsThrough() {
        assertMacroExpansion(
            #"#log(logger, makeMessage(for: user), tag: .api)"#,
            expandedSource: """
            logger.log(.info, makeMessage(for: user), tag: .api, \
            file: #fileID, function: #function, line: #line)
            """,
            macros: macros
        )
    }

    func testMeasureMacroLowersToInjectedSignposter() {
        assertMacroExpansion(
            """
            #measure(signposter, "loadUsers") {
                try repo.all()
            }
            """,
            expandedSource: """
            signposter.measure("loadUsers") {
                try repo.all()
            }
            """,
            macros: macros
        )
    }
}
