import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion of `#measure(signposter, "name") { body }`.
///
/// Lowers to: `signposter.measure("name") { body }`.
public struct MeasureMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = Array(node.arguments)
        guard arguments.count >= 2 else {
            throw MacroError("#measure requires a signposter and a name: #measure(signposter, \"name\") { … }")
        }
        let signposterExpr = arguments[0].expression
        let nameExpr = arguments[1].expression

        // The trailing closure may be in `node.trailingClosure` or as the
        // last labeled argument.
        let closure: ExprSyntax
        if let trailing = node.trailingClosure {
            closure = ExprSyntax(trailing)
        } else if let last = arguments.last?.expression, arguments.count > 2 {
            closure = last
        } else {
            throw MacroError("#measure requires a trailing closure")
        }

        return """
        \(signposterExpr).measure(\(nameExpr)) \(closure)
        """
    }
}
