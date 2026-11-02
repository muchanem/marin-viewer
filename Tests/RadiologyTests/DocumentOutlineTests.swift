import Foundation
import Testing
@testable import Radiology

struct DocumentOutlineTests {
    @Test func methodsAndNestedFunctionsAreFlatAndLargestFirst() async throws {
        let text = """
        struct Shape { side: u32 }
        impl Shape {
            fn short() {}
            fn larger(
                x: u32,
            ) -> u32 {
                const LOCAL: u32 = 1;
                fn nested() { }
                x + LOCAL
            }
            fn tied() {}
        }
        """
        let buffer = try SourceBuffer(path: "shape.rs", data: Data(text.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let outline = DocumentOutline(symbols: syntax.symbols, buffer: buffer)
        #expect(outline.functions.map { $0.symbol.name } == ["larger", "short", "nested", "tied"])
        #expect(outline.functions.map(\.lineCount) == [7, 1, 1, 1])
        #expect(Set(outline.functions.map(\.id)).count == 4)
        func flatten(_ nodes: [OutlineNode]) -> [DocumentSymbol] {
            nodes.flatMap { [$0.symbol] + flatten($0.children) }
        }
        let remaining = flatten(outline.declarations)
        #expect(remaining.contains { $0.name == "LOCAL" }, "non-callable descendants remain accessible")
        #expect(!remaining.contains { SyntaxSnapshot.callableKinds.contains($0.kind) })
        #expect(Set(remaining.map(\.id)).count == remaining.count)
        #expect(outline.functions.allSatisfy { syntax.symbols.contains($0.symbol) }, "navigation uses original ranges and IDs")
    }

    @Test func halfOpenLineSpanUsesBytesAcrossMultilineUnicode() throws {
        let buffer = try SourceBuffer(path: "a.rs", data: Data("fn café(\n    emoji: &str,\n) { let x = \"👩🏽‍💻\"; }\nnext\n".utf8))
        let symbol = DocumentSymbol(name: "café", kind: "function", byteRange: 0..<buffer.byteOffset(line: 4),
                                    selectionByteRange: 3..<8, depth: 0)
        #expect(DocumentOutline.lineCount(of: symbol, in: buffer) == 3)
    }

    @Test func identicalFilesStillInvalidateOnEitherPathChange() async throws {
        let data = Data("fn same() {}\n".utf8)
        let first = try SourceBuffer(path: "first.rs", data: data)
        let second = try SourceBuffer(path: "second.rs", data: data)
        let syntax = try #require(try await SyntaxWorker().parse(first))
        let identity = SourceContentIdentity(data)
        let old = DocumentOutline.InputKey(path: first.path, syntaxPath: first.path, sourceIdentity: identity, symbols: syntax.symbols)
        let loading = DocumentOutline.InputKey(path: second.path, syntaxPath: first.path, sourceIdentity: identity, symbols: syntax.symbols)
        let loaded = DocumentOutline.InputKey(path: second.path, syntaxPath: second.path, sourceIdentity: identity, symbols: syntax.symbols)
        #expect(old != loading)
        #expect(loading != loaded)
        let refreshed = DocumentOutline(symbols: syntax.symbols, buffer: second)
        #expect(refreshed.path == second.path)
        #expect(refreshed.functions.first?.id == syntax.symbols.first?.id)
    }
}
