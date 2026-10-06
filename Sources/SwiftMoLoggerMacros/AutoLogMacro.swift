import SwiftSyntax
import SwiftSyntaxMacros

/// `@AutoLog` adds a `__autoLog()` helper to a class or actor. A method that
/// calls it logs a `trace` entry ("→ <method>") through the type's `logger`.
///
/// The `memberAttribute` role currently adds nothing (methods are not
/// rewritten), so only methods that call `__autoLog()` are logged.
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

        // The type supplies its own injected `logger: MoLogger` property; the
        // helper logs through it, so there's no global logger involved.
        // Emit a single helper that the method bodies can call manually
        // (e.g. `__autoLog("purchase")`). Body rewriting via macros is still
        // an evolving area in Swift — keeping the surface minimal avoids
        // emitting code that won't typecheck for every adopter shape.
        // The method name is marked public: it isn't user data, and the entry
        // must read the same when 5.0 makes unmarked interpolations private.
        let helper: DeclSyntax = """
        /// Synthesised by @AutoLog. Call at the top of every traced method
        /// to emit a structured entry log; the symbol name keeps it grep-able.
        @inline(__always)
        fileprivate func __autoLog(_ method: String = #function,
                                   file: String = #fileID,
                                   line: Int = #line) {
            logger.trace("→ \\(method, privacy: .public)", tag: .Development.debug,
                         file: file, function: method, line: line)
        }
        """
        return [helper]
    }
}
