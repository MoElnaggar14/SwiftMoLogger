import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct SwiftMoLoggerMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        LogMacro.self,
        MeasureMacro.self,
        AutoLogMacro.self
    ]
}
