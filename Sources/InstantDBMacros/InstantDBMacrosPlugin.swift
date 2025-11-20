import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct InstantDBMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        InstantEntityMacro.self
    ]
}
