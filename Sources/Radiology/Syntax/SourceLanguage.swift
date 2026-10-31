import Foundation
import SwiftTreeSitter
import TreeSitterC
import TreeSitterCPP
import TreeSitterGo
import TreeSitterJavaScript
import TreeSitterKotlin
import TreeSitterPython
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript

/// One native Tree-sitter grammar plus the query files that describe its
/// highlights, folds, declarations, and lexical scopes.
///
/// Grammars are linked statically; queries live beside the code in
/// `Sources/Radiology/Queries` and ship in the module resource bundle.
/// `plans/tree-sitter.md` records the provenance and licence of each one.
struct SourceLanguage: Identifiable, Sendable {
    /// Stable registry key, the `Queries/` sub-directory name, and the
    /// identifier used in diagnostics.
    let id: String
    /// Name shown in the source footer and the outline's empty state.
    let displayName: String
    /// Lowercased path extensions this grammar claims.
    let extensions: Set<String>
    /// Query directories concatenated in order. Later patterns win, so an
    /// overlay such as JSX can refine the shared ECMAScript core.
    let queryDirectories: [String]
    private let grammar: @Sendable () -> OpaquePointer

    var treeSitterLanguage: Language { Language(language: grammar()) }

    init(id: String, displayName: String, extensions: Set<String>,
         queryDirectories: [String]? = nil, grammar: @escaping @Sendable () -> OpaquePointer) {
        self.id = id
        self.displayName = displayName
        self.extensions = extensions
        self.queryDirectories = queryDirectories ?? [id]
        self.grammar = grammar
    }
}

/// Maps a file to the grammar that can parse it.
///
/// JavaScript and TypeScript need two grammars each: the JSX dialects are a
/// different language, so `.jsx` uses the JSX-capable JavaScript grammar and
/// `.tsx` uses the dedicated TSX grammar rather than the TypeScript one.
enum SourceLanguageRegistry {
    static let all: [SourceLanguage] = [
        SourceLanguage(id: "swift", displayName: "Swift", extensions: ["swift"],
                       grammar: { tree_sitter_swift() }),
        SourceLanguage(id: "rust", displayName: "Rust", extensions: ["rs"],
                       grammar: { tree_sitter_rust() }),
        SourceLanguage(id: "go", displayName: "Go", extensions: ["go"],
                       grammar: { tree_sitter_go() }),
        SourceLanguage(id: "python", displayName: "Python", extensions: ["py", "pyi"],
                       grammar: { tree_sitter_python() }),
        SourceLanguage(id: "javascript", displayName: "JavaScript",
                       extensions: ["js", "jsx", "mjs", "cjs"],
                       queryDirectories: ["ecmascript", "javascript", "jsx"],
                       grammar: { tree_sitter_javascript() }),
        SourceLanguage(id: "typescript", displayName: "TypeScript",
                       extensions: ["ts", "mts", "cts"],
                       queryDirectories: ["ecmascript", "typescript"],
                       grammar: { tree_sitter_typescript() }),
        SourceLanguage(id: "tsx", displayName: "TypeScript JSX", extensions: ["tsx"],
                       queryDirectories: ["ecmascript", "typescript", "jsx"],
                       grammar: { tree_sitter_tsx() }),
        SourceLanguage(id: "kotlin", displayName: "Kotlin", extensions: ["kt", "kts"],
                       grammar: { tree_sitter_kotlin() }),
        SourceLanguage(id: "c", displayName: "C", extensions: ["c"],
                       grammar: { tree_sitter_c() }),
        // Plain .h headers can contain either language; C++ accepts common C
        // declarations too and retains C++ class/template structure.
        SourceLanguage(id: "cpp", displayName: "C++", extensions: ["cpp", "cc", "cxx", "c++", "h", "hpp", "hh", "hxx", "h++", "ipp", "inl", "tpp", "tcc"],
                       queryDirectories: ["c", "cpp"],
                       grammar: { tree_sitter_cpp() }),
    ]

    private static let byExtension: [String: SourceLanguage] = all.reduce(into: [:]) { table, language in
        for fileExtension in language.extensions { table[fileExtension] = language }
    }

    static func language(for path: String) -> SourceLanguage? {
        let ext = URL(filePath: path).pathExtension
        // Unix convention: .C is C++, while .c is C.
        if ext == "C" { return language(id: "cpp") }
        return byExtension[ext.lowercased()]
    }

    static func language(id: String) -> SourceLanguage? {
        all.first { $0.id == id }
    }
}
