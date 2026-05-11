import SwiftSyntax
import SwiftSyntaxMacros

/// Expansion of `#measure("name") { body }`.
///
/// Lowers to: `LogSignpost.measure("name") { body }`.
public struct MeasureMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let arguments = node.arguments
        guard let nameExpr = arguments.first?.expression else {
            throw MacroError("#measure requires a name argument")
        }

        // The trailing closure may be in `node.trailingClosure` or as the
        // last labeled argument.
        let closure: ExprSyntax
        if let trailing = node.trailingClosure {
            closure = ExprSyntax(trailing)
        } else if let last = arguments.last?.expression, arguments.count > 1 {
            closure = last
        } else {
            throw MacroError("#measure requires a trailing closure")
        }

        return """
        LogSignpost.measure(\(nameExpr)) \(closure)
        """
    }
}
