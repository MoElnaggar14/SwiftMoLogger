import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
@testable import SwiftMoLoggerMacros

final class LogMacroTests: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "log": LogMacro.self,
        "measure": MeasureMacro.self
    ]

    func testLogMacroExpandsWithDefaults() {
        assertMacroExpansion(
            #"#log("hello")"#,
            expandedSource: #"SwiftMoLogger.log(.info, "hello", tag: nil, file: #fileID, function: #function, line: #line)"#,
            macros: macros
        )
    }

    func testLogMacroForwardsLevelAndTag() {
        assertMacroExpansion(
            #"#log("oops", level: .error, tag: .api)"#,
            expandedSource: #"SwiftMoLogger.log(.error, "oops", tag: .api, file: #fileID, function: #function, line: #line)"#,
            macros: macros
        )
    }

    func testMeasureMacroLowersToSignpost() {
        assertMacroExpansion(
            """
            #measure("loadUsers") {
                try repo.all()
            }
            """,
            expandedSource: """
            LogSignpost.measure("loadUsers") {
                try repo.all()
            }
            """,
            macros: macros
        )
    }
}
