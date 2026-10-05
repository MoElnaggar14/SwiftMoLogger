import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion of `#log(logger, "msg", level: .info, tag: .api)`.
///
/// Lowers to:
///
/// ```swift
/// <logger>.log(<level>, <message>, tag: <tag>,
///              file: #fileID, function: #function, line: #line)
/// ```
public struct LogMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = Array(node.arguments)
        guard arguments.count >= 2 else {
            throw MacroError("#log requires a logger and a message: #log(logger, \"message\")")
        }
        let loggerExpr = arguments[0].expression
        let messageExpr = arguments[1].expression

        var level: ExprSyntax = ".info"
        var tag: ExprSyntax = "nil"

        for argument in arguments.dropFirst(2) {
            switch argument.label?.text {
            case "level":
                level = argument.expression
            case "tag":
                tag = argument.expression
            default:
                continue
            }
        }

        return """
        \(loggerExpr).log(\(level), \(messageExpr), tag: \(tag), file: #fileID, function: #function, line: #line)
        """
    }
}

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
