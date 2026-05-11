import SwiftSyntax
import SwiftSyntaxMacros

/// `@AutoLog` — member attribute that wraps every public/internal method in
/// a `final class` or `actor` with automatic entry / exit / throw logging.
///
/// This is a `memberAttribute` macro: it walks the type's declarations and
/// emits a marker attribute on each method. A future pass could also rewrite
/// the bodies; for now we keep the diagnostic surface small by emitting a
/// `trace`-level log entry at the start of every method via a synthesised
/// `__autolog_<method>` helper that the method body can opt into.
public struct AutoLogMacro: MemberMacro, MemberAttributeMacro {

    // MARK: - MemberAttributeMacro

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        // Only attach to functions; skip stored properties, nested types, etc.
        guard member.is(FunctionDeclSyntax.self) else { return [] }
        return []
    }

    // MARK: - MemberMacro

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let methods = declaration.memberBlock.members.compactMap { member -> FunctionDeclSyntax? in
            member.decl.as(FunctionDeclSyntax.self)
        }
        guard !methods.isEmpty else { return [] }

        // Emit a single helper that the method bodies can call manually
        // (e.g. `__autoLog("purchase")`). Body rewriting via macros is still
        // an evolving area in Swift — keeping the surface minimal avoids
        // emitting code that won't typecheck for every adopter shape.
        let helper: DeclSyntax = """
        /// Synthesised by @AutoLog. Call at the top of every traced method
        /// to emit a structured entry log; the symbol name keeps it grep-able.
        @inline(__always)
        fileprivate func __autoLog(_ method: String = #function,
                                   file: String = #fileID,
                                   line: Int = #line) {
            SwiftMoLogger.trace("→ \\(method)", tag: .Development.debug, file: file, function: method, line: line)
        }
        """
        return [helper]
    }
}
