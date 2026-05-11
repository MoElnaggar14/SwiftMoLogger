import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion of `#log("msg", level: .info, tag: .api)`.
///
/// Lowers to:
///
/// ```swift
/// SwiftMoLogger.log(<level>, <message>, tag: <tag>,
///                   file: #fileID, function: #function, line: #line)
/// ```
public struct LogMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = node.arguments
        guard let messageExpr = arguments.first?.expression else {
            throw MacroError("#log requires a message argument")
        }

        var level: ExprSyntax = ".info"
        var tag: ExprSyntax = "nil"

        for argument in arguments.dropFirst() {
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
        SwiftMoLogger.log(\(level), \(messageExpr), tag: \(tag), file: #fileID, function: #function, line: #line)
        """
    }
}

struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
