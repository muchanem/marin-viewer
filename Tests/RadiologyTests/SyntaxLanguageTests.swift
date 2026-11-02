import Foundation
import Testing
@testable import Radiology

/// Per-grammar regressions: highlights, declarations, scopes, and folds for
/// each registered language, plus the dialect distinctions that need two
/// different grammars.
struct SyntaxLanguageTests {
    @Test(arguments: ["sample.swift", "sample.rs", "sample.go", "sample.py", "sample.js",
                      "sample.jsx", "sample.ts", "sample.tsx", "sample.kt", "sample.kts", "sample.c", "sample.cpp"])
    func everySupportedDialectProvidesFunctionBodyFolds(_ fixture: String) async throws {
        let (_, snapshot) = try await SyntaxFixtures.snapshot(fixture)
        #expect(snapshot.folds.contains { $0.kind == "function" },
                "\(fixture) must expose function bodies for default collapse")
    }

    @Test func rustHighlightsDeclarationsScopesAndFolds() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.rs")
        #expect(snapshot.languageID == "rust")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlight(named: "keyword.type", text: "struct", in: buffer))
        #expect(snapshot.highlight(named: "function", text: "render", in: buffer))
        #expect(snapshot.highlight(named: "function.macro", text: "println", in: buffer))
        #expect(snapshot.highlight(named: "type.builtin", text: "usize", in: buffer))
        #expect(snapshot.highlight(named: "comment.documentation", text: "/// Doc comment\n", in: buffer))
        #expect(snapshot.symbol("type", "Scan"))
        #expect(snapshot.symbol("enum", "Modality"))
        #expect(snapshot.symbol("protocol", "Render"))
        #expect(snapshot.symbol("module", "helpers"))
        #expect(snapshot.symbol("constant", "MAX_SCANS"))
        #expect(snapshot.symbols.contains { $0.kind == "function" && $0.name == "render" && $0.depth > 0 })
        #expect(snapshot.scopes.contains { $0.kind == "closure" })
        #expect(snapshot.folds.contains { $0.kind == "function" })
        #expect(snapshot.folds.contains { $0.kind == "type" })
    }

    @Test func goHighlightsDeclarationsScopesAndFolds() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.go")
        #expect(snapshot.languageID == "go")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlight(named: "keyword.function", text: "func", in: buffer))
        #expect(snapshot.highlight(named: "namespace", text: "scan", in: buffer))
        #expect(snapshot.highlight(named: "type.builtin", text: "string", in: buffer))
        // `#any-of?` predicates must be evaluated against UTF-8 byte ranges.
        #expect(snapshot.highlight(named: "function.builtin", text: "append", in: buffer))
        #expect(!snapshot.highlights.contains { $0.name == "function.builtin" && buffer.text(in: $0.byteRange) == "New" })
        #expect(snapshot.symbol("module", "scan"))
        #expect(snapshot.symbol("type", "Scan"))
        #expect(snapshot.symbol("method", "Render"))
        #expect(snapshot.symbol("function", "New"))
        #expect(snapshot.scopes.contains { $0.kind == "closure" })
        #expect(snapshot.folds.contains { $0.kind == "imports" })
        #expect(snapshot.folds.contains { $0.kind == "function" })
    }

    @Test func pythonHighlightsDeclarationsScopesAndFolds() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.py")
        #expect(snapshot.languageID == "python")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlight(named: "keyword.function", text: "def", in: buffer))
        #expect(snapshot.highlight(named: "keyword.coroutine", text: "async", in: buffer))
        #expect(snapshot.highlight(named: "attribute", text: "@dataclass", in: buffer))
        #expect(snapshot.highlight(named: "function.builtin", text: "range", in: buffer))
        #expect(snapshot.highlight(named: "variable.builtin", text: "self", in: buffer))
        #expect(snapshot.symbol("type", "Scan"))
        #expect(snapshot.symbol("function", "load"))
        #expect(snapshot.symbols.contains { $0.name == "render" && $0.depth > 0 })
        #expect(snapshot.scopes.contains { $0.kind == "type" })
        #expect(snapshot.folds.contains { $0.kind == "function" })
        #expect(snapshot.folds.contains { $0.kind == "type" })
    }

    @Test func javaScriptHighlightsDeclarationsScopesAndFolds() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.js")
        #expect(snapshot.languageID == "javascript")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlight(named: "keyword.type", text: "class", in: buffer))
        #expect(snapshot.highlight(named: "function.method", text: "render", in: buffer))
        #expect(snapshot.highlight(named: "property", text: "#secret", in: buffer))
        #expect(snapshot.highlight(named: "variable.builtin", text: "console", in: buffer))
        #expect(snapshot.highlight(named: "constant", text: "MAX_SCANS", in: buffer))
        #expect(snapshot.symbol("type", "Scan"))
        #expect(snapshot.symbol("method", "render"))
        #expect(snapshot.symbol("function", "load"))
        #expect(snapshot.symbol("function", "double"))
        #expect(snapshot.scopes.contains { $0.kind == "closure" })
        #expect(snapshot.folds.contains { $0.kind == "type" })
    }

    @Test func typeScriptHighlightsDeclarationsScopesAndFolds() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.ts")
        #expect(snapshot.languageID == "typescript")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlight(named: "keyword.type", text: "interface", in: buffer))
        #expect(snapshot.highlight(named: "keyword.modifier", text: "readonly", in: buffer))
        #expect(snapshot.highlight(named: "type.builtin", text: "string", in: buffer))
        #expect(snapshot.symbol("protocol", "Renderer"))
        #expect(snapshot.symbol("typealias", "Modality"))
        #expect(snapshot.symbol("enum", "Level"))
        #expect(snapshot.symbol("case", "Low"))
        #expect(snapshot.symbol("module", "Helpers"))
        #expect(snapshot.symbol("type", "Scan"))
        #expect(snapshot.scopes.contains { $0.kind == "protocol" })
        #expect(snapshot.folds.contains { $0.kind == "type" })
    }

    @Test func kotlinHighlightsDeclarationsScopesAndFolds() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.kt")
        #expect(snapshot.languageID == "kotlin")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlight(named: "keyword.function", text: "fun", in: buffer))
        #expect(snapshot.highlight(named: "namespace", text: "radiology.scan", in: buffer))
        #expect(snapshot.highlight(named: "type.builtin", text: "String", in: buffer))
        #expect(snapshot.highlight(named: "constant", text: "XRAY", in: buffer))
        // `return` must colour the keyword alone, not the expression it returns.
        #expect(snapshot.highlight(named: "keyword.return", text: "return", in: buffer))
        #expect(snapshot.symbol("type", "Scan"))
        #expect(snapshot.symbol("type", "Modality"))
        #expect(snapshot.symbol("typealias", "Titles"))
        #expect(snapshot.symbol("initializer", "constructor"))
        #expect(snapshot.symbol("case", "XRAY"))
        // Function-local `val`s are not declarations of the file.
        #expect(!snapshot.symbol("property", "parts"))
        #expect(snapshot.scopes.contains { $0.kind == "closure" })
        #expect(snapshot.folds.contains { $0.kind == "imports" })
    }

    @Test func kotlinScriptsUseTheSameGrammar() async throws {
        let (_, snapshot) = try await SyntaxFixtures.snapshot("sample.kts")
        #expect(snapshot.languageID == "kotlin")
        #expect(!snapshot.hasParseErrors)
        // A script has top-level statements and no enclosing declaration.
        #expect(snapshot.symbol("function", "collect"))
        #expect(snapshot.symbol("type", "Report"))
        #expect(snapshot.symbol("property", "scanRoot"))
    }

    // MARK: - Dialects needing a second grammar

    @Test func jsxUsesTheJavaScriptGrammarAndTagsElements() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.jsx")
        #expect(snapshot.languageID == "javascript")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlight(named: "tag", text: "ul", in: buffer))
        #expect(snapshot.highlight(named: "tag", text: "Badge", in: buffer))
        #expect(snapshot.highlight(named: "attribute", text: "className", in: buffer))
        #expect(snapshot.symbol("function", "ScanList"))
    }

    @Test func tsxUsesTheTsxGrammarAndKeepsTypeScriptStructure() async throws {
        let (buffer, snapshot) = try await SyntaxFixtures.snapshot("sample.tsx")
        #expect(snapshot.languageID == "tsx")
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlight(named: "tag", text: "ul", in: buffer))
        #expect(snapshot.highlight(named: "attribute", text: "data-count", in: buffer))
        #expect(snapshot.highlight(named: "type.builtin", text: "number", in: buffer))
        #expect(snapshot.symbol("protocol", "Props"))
    }

    /// The JSX dialects are a different language, not a superset: each file
    /// must reach the grammar that can actually parse it.
    @Test func jsxAndTsxNeedTheirOwnGrammars() async throws {
        let jsxData = try SyntaxFixtures.buffer("sample.tsx").data
        let asTSX = try #require(try await SyntaxWorker().parse(SourceBuffer(path: "View.tsx", data: jsxData)))
        let asTypeScript = try #require(try await SyntaxWorker().parse(SourceBuffer(path: "View.ts", data: jsxData)))
        #expect(!asTSX.hasParseErrors)
        #expect(asTypeScript.hasParseErrors, "the TypeScript grammar must not silently accept JSX")

        // Conversely, a TypeScript angle-bracket assertion is ambiguous in TSX.
        let assertion = Data("const value = <string>(input as unknown);\n".utf8)
        let typeScript = try #require(try await SyntaxWorker().parse(SourceBuffer(path: "Cast.ts", data: assertion)))
        let tsx = try #require(try await SyntaxWorker().parse(SourceBuffer(path: "Cast.tsx", data: assertion)))
        #expect(!typeScript.hasParseErrors)
        #expect(tsx.hasParseErrors, "the TSX grammar reads `<string>` as an element, not a cast")
    }

    @Test func javaScriptGrammarAlsoParsesJsxInsidePlainJsFiles() async throws {
        let data = Data("export const View = () => <main className=\"x\">hi</main>;\n".utf8)
        let snapshot = try #require(try await SyntaxWorker().parse(SourceBuffer(path: "View.js", data: data)))
        #expect(!snapshot.hasParseErrors)
        #expect(snapshot.highlights.contains { $0.name == "tag" })
    }
}
