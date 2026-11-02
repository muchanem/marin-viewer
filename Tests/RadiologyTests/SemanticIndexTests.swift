import Foundation
import Testing
@testable import Radiology

struct SemanticIndexTests {
    static let fixtureRoot = Bundle.module.resourceURL!.appending(path: "Fixtures/scip-rust")

    static func loadFixture() throws -> (SCIPIndex, SemanticIndex) {
        let data = try Data(contentsOf: fixtureRoot.appending(path: "index.scip"))
        let raw = try SCIPDecoder.decode(data)
        return (raw, SemanticIndex(indexes: [raw]))
    }

    static func buffer(_ relative: String) throws -> SourceBuffer {
        try SourceBuffer(path: relative, data: Data(contentsOf: fixtureRoot.appending(path: relative)))
    }

    @Test func decodesARealRustAnalyzerIndex() throws {
        let (raw, index) = try Self.loadFixture()
        #expect(raw.metadata.toolName == "rust-analyzer")
        #expect(raw.metadata.projectRoot.hasPrefix("file://"))
        #expect(raw.documents.map(\.relativePath).sorted() == ["src/lib.rs", "src/shapes.rs"])
        #expect(raw.documents.allSatisfy { $0.positionEncoding == 1 })
        #expect(index.documents["src/shapes.rs"]?.encoding == .utf8)
        let total = index.symbols.first { $0.value.displayName == "total_area" }
        #expect(total?.value.kind.name == "Function")
        #expect(total?.value.signature == "pub fn total_area(items: &[Circle]) -> f64")
        #expect(total?.value.documentation.first?.contains("café 🚀") == true, "UTF-8 documentation survives decoding")
    }

    @Test func definitionsResolveAcrossFilesAndLocalsStayPerDocument() throws {
        let (_, index) = try Self.loadFixture()
        let circle = SemanticSymbolID(symbol: "rust-analyzer cargo ra_fixture 0.1.0 shapes/Circle#", document: "src/lib.rs")
        #expect(!circle.isLocal)
        let definitions = index.definitions(of: circle)
        #expect(definitions.count == 1)
        #expect(definitions.first?.path == "src/shapes.rs")
        #expect(definitions.first?.range == SCIPRange(startLine: 0, startCharacter: 11, endLine: 0, endCharacter: 17))
        let libLocal = SemanticSymbolID(symbol: "local 0", document: "src/lib.rs")
        let shapesLocal = SemanticSymbolID(symbol: "local 0", document: "src/shapes.rs")
        #expect(libLocal != shapesLocal)
        #expect(index.displayName(libLocal) == "items")
        #expect(index.displayName(shapesLocal) == "radius")
        #expect(index.definitions(of: libLocal).first?.path == "src/lib.rs")
        #expect(index.definitions(of: shapesLocal).first?.path == "src/shapes.rs")
    }

    @Test func caretResolutionUsesByteOffsetsAndHalfOpenRanges() throws {
        let (_, index) = try Self.loadFixture()
        let lib = try Self.buffer("src/lib.rs")
        let semantics = DocumentSemantics.make(document: index.documents["src/lib.rs"]!, buffer: lib)
        #expect(semantics.unmappedCount == 0)
        // `pub fn total_area(items: &[Circle]) -> f64 {` is line 5 (1-based); `Circle` starts at column 27.
        let circleStart = lib.byteOffset(line: 5, column: 27)
        let onCircle = index.target(in: semantics, at: circleStart + 2)
        #expect(onCircle?.displayName == "Circle")
        #expect(onCircle?.kind.name == "Struct")
        #expect(onCircle?.hasDefinition == true)
        #expect(onCircle?.definitions.first?.path == "src/shapes.rs")
        #expect(onCircle?.isOnDefinition == false)
        // Half-open: the byte right after `Circle` is the `]`. Only the whole-file crate
        // module occurrence covers it, and multi-line occurrences are not caret targets.
        #expect(index.target(in: semantics, at: lib.byteOffset(line: 5, column: 33)) == nil)
        // On the definition of `total_area` itself there is nothing to jump to, but the symbol is known.
        let onDefinition = index.target(in: semantics, at: lib.byteOffset(line: 5, column: 8))
        #expect(onDefinition?.displayName == "total_area")
        #expect(onDefinition?.isOnDefinition == true)
        #expect(onDefinition?.hasDefinition == false)
        // `item.area()` on line 8 resolves the method to shapes.rs.
        let area = index.target(in: semantics, at: lib.byteOffset(line: 8, column: 21))
        #expect(area?.displayName == "area")
        #expect(area?.definitions.first?.path == "src/shapes.rs")
        #expect(area?.definitions.first?.range.startLine == 6)
        // `+=` is an external core operator: known symbol, no in-repository target.
        let plusEquals = index.target(in: semantics, at: lib.byteOffset(line: 8, column: 12))
        #expect(plusEquals != nil)
        #expect(plusEquals?.hasDefinition == false)
        #expect(plusEquals?.symbol.symbol.hasPrefix("rust-analyzer cargo core") == true)
    }

    @Test func shorthandFieldPrefersTheRepositorySymbolOverTheLocal() throws {
        let (_, index) = try Self.loadFixture()
        let shapes = try Self.buffer("src/shapes.rs")
        let semantics = DocumentSemantics.make(document: index.documents["src/shapes.rs"]!, buffer: shapes)
        // `Circle { radius }` on line 6: both `local 0` and `Circle#radius.` cover columns 47..<53.
        let target = index.target(in: semantics, at: shapes.byteOffset(line: 6, column: 48))
        #expect(target?.symbol.symbol == "rust-analyzer cargo ra_fixture 0.1.0 shapes/Circle#radius.")
        #expect(target?.definitions.first?.range.startLine == 1)
        #expect(index.referenceCount(of: target!.symbol) == 2)

        let selection = try #require(index.occurrenceSelection(in: semantics, at: shapes.byteOffset(line: 6, column: 48)))
        #expect(selection.symbol == target?.symbol)
        #expect(selection.activeByteRange == target?.byteRange)
        #expect(selection.byteRanges.count == 3, "the field definition and both references are included")
        #expect(selection.byteRanges.allSatisfy { range in
            semantics.occurrences.contains { $0.symbol == selection.symbol && $0.byteRange == range }
        }, "the overlapping same-spelling local must not leak into the field selection")
    }

    @Test func occurrenceSelectionUsesIdentityWithoutRequiringARepositoryDefinition() throws {
        let (_, index) = try Self.loadFixture()
        let lib = try Self.buffer("src/lib.rs")
        let semantics = DocumentSemantics.make(document: index.documents[lib.path]!, buffer: lib)
        let selection = try #require(index.occurrenceSelection(in: semantics, at: lib.byteOffset(line: 8, column: 12)))
        #expect(selection.symbol.symbol.hasPrefix("rust-analyzer cargo core"))
        #expect(index.definitions(of: selection.symbol).isEmpty)
        #expect(!selection.byteRanges.isEmpty)
        #expect(index.occurrenceSelection(in: semantics, at: lib.byteOffset(line: 3, column: 0)) == nil,
                "whitespace must not fabricate a symbol")
    }

    @Test func occurrenceSelectionPreservesUnicodeByteBoundariesUntilTextKit() throws {
        let text = "let 🚀café = 1;\nuse(🚀café);\n"
        let buffer = try SourceBuffer(path: "unicode.rs", data: Data(text.utf8))
        let symbol = "rust-analyzer cargo unicode 0.1.0 crate/café."
        var definition = SCIPOccurrence()
        definition.range = SCIPRange(startLine: 0, startCharacter: 4, endLine: 0, endCharacter: 13)
        definition.symbol = symbol
        definition.symbolRoles = SCIPSymbolRole.definition
        var reference = SCIPOccurrence()
        reference.range = SCIPRange(startLine: 1, startCharacter: 4, endLine: 1, endCharacter: 13)
        reference.symbol = symbol
        var document = SCIPDocument()
        document.relativePath = buffer.path
        document.positionEncoding = 1
        document.occurrences = [definition, reference]
        var raw = SCIPIndex()
        raw.documents = [document]
        let index = SemanticIndex(indexes: [raw])
        let semantics = DocumentSemantics.make(document: index.documents[buffer.path]!, buffer: buffer)

        let selection = try #require(index.occurrenceSelection(in: semantics, at: 6))
        #expect(selection.byteRanges == [4..<13, 23..<32])
        #expect(selection.byteRanges.map(buffer.utf16Range(forByteRange:)) == [
            NSRange(location: 4, length: 6), NSRange(location: 20, length: 6),
        ])
    }

    @Test func searchEntriesRankExactPrefixInitialsAndFuzzy() throws {
        let (_, index) = try Self.loadFixture()
        let names = index.searchEntries.map(\.name)
        #expect(names.contains("Circle") && names.contains("total_area") && names.contains("area") && names.contains("new"))
        #expect(!names.contains("items"), "document-local symbols are not repository symbols")
        let entries = ["Circle", "CircleArea", "total_area", "tally", "SnapshotBootstrapGlobals"].enumerated().map { offset, name in
            SymbolSearchEntry(id: SemanticSymbolID(symbol: "s \(name)", document: ""), name: name,
                              kind: SemanticSymbolKind(rawValue: 17),
                              position: SemanticPosition(path: "f\(offset).rs", range: SCIPRange(startLine: offset, startCharacter: 0, endLine: offset, endCharacter: 1), encoding: .utf8),
                              definitionCount: 1)
        }
        #expect(SymbolSearch.rank("circle", in: entries).map(\.entry.name) == ["Circle", "CircleArea"])
        #expect(SymbolSearch.rank("circle", in: entries).map(\.tier) == [0, 1])
        #expect(SymbolSearch.rank("sbg", in: entries).first?.entry.name == "SnapshotBootstrapGlobals")
        #expect(SymbolSearch.rank("sbg", in: entries).first?.tier == 2)
        #expect(SymbolSearch.rank("ta", in: entries).map(\.entry.name) == ["tally", "total_area", "SnapshotBootstrapGlobals"], "prefix, then initials, then fuzzy")
        #expect(SymbolSearch.rank("tlar", in: entries).map(\.entry.name) == ["total_area"], "fuzzy subsequence")
        #expect(SymbolSearch.rank("zzz", in: entries).isEmpty)
    }

    @Test func columnConversionsHonorEncodingsAndRejectOutOfBounds() throws {
        let buffer = try SourceBuffer(path: "u.rs", data: Data("let 🚀café = 1;\nnext\n".utf8))
        // 🚀 is 4 UTF-8 bytes, 2 UTF-16 units, 1 UTF-32 unit; é is 2/1/1.
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 4, encoding: .utf8) == 4)
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 8, encoding: .utf8) == 8)
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 6, encoding: .utf8) == 4, "inside the rocket clamps to its start")
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 6, encoding: .utf16) == 8)
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 5, encoding: .utf16) == 4, "a surrogate split clamps to the scalar start")
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 5, encoding: .utf32) == 8)
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 9, encoding: .utf32) == 13)
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 14, encoding: .utf32) == 18, "end of line is addressable")
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 15, encoding: .utf32) == nil)
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: 99, encoding: .utf8) == nil)
        #expect(buffer.byteOffset(zeroBasedLine: 5, column: 0, encoding: .utf8) == nil)
        #expect(buffer.byteOffset(zeroBasedLine: 0, column: -1, encoding: .utf8) == nil)
        #expect(buffer.position(forByte: 8, encoding: .utf16) == (0, 6))
        #expect(buffer.position(forByte: 8, encoding: .utf32) == (0, 5))
        #expect(buffer.position(forByte: 22, encoding: .utf8) == (1, 3))
        let multi = SCIPRange(startLine: 0, startCharacter: 4, endLine: 1, endCharacter: 2)
        #expect(buffer.byteRange(for: multi, encoding: .utf8) == 4..<21)
        #expect(buffer.byteRange(for: SCIPRange(startLine: 0, startCharacter: 4, endLine: 3, endCharacter: 0), encoding: .utf8) == nil)
    }

    @Test func staleAndMalformedDataDegradeWithoutFabricatingPositions() throws {
        let (_, index) = try Self.loadFixture()
        let shortened = try SourceBuffer(path: "src/shapes.rs", data: Data("pub struct Circle {\n}\n".utf8))
        let semantics = DocumentSemantics.make(document: index.documents["src/shapes.rs"]!, buffer: shortened)
        #expect(semantics.unmappedCount > 0)
        #expect(semantics.occurrences.allSatisfy { $0.byteRange.upperBound <= shortened.data.count })
        #expect(throws: SCIPDecoder.Failure.self) { try SCIPDecoder.decode(Data([0x0A, 0xFF, 0xFF])) }
        let empty = try SCIPDecoder.decode(Data())
        #expect(empty.documents.isEmpty)
        var escaping = SCIPDocument()
        escaping.relativePath = "../outside.rs"
        var raw = SCIPIndex()
        raw.documents = [escaping]
        #expect(SemanticIndex(indexes: [raw]).documents.isEmpty, "paths escaping the project root are dropped")
    }

    @Test func typedRangesAndUnknownFieldsDecode() throws {
        // Hand-encoded Index: one document with a typed single-line range (field 8),
        // a typed multi-line enclosing range (field 11) and an unknown field 99.
        func varint(_ value: Int) -> [UInt8] {
            var value = UInt64(value); var out: [UInt8] = []
            repeat { var byte = UInt8(value & 0x7F); value >>= 7; if value != 0 { byte |= 0x80 }; out.append(byte) } while value != 0
            return out
        }
        func field(_ number: Int, bytes: [UInt8]) -> [UInt8] { varint(number << 3 | 2) + varint(bytes.count) + bytes }
        func field(_ number: Int, int value: Int) -> [UInt8] { varint(number << 3 | 0) + varint(value) }
        let single = field(1, int: 3) + field(2, int: 4) + field(3, int: 9)
        let multi = field(1, int: 2) + field(2, int: 0) + field(3, int: 6) + field(4, int: 1)
        let occurrence = field(8, bytes: single) + field(2, bytes: Array("x y z 1 a#".utf8)) + field(3, int: 1) + field(11, bytes: multi) + field(99, int: 7)
        let document = field(1, bytes: Array("a.go".utf8)) + field(2, bytes: occurrence) + field(6, int: 2)
        let index = try SCIPDecoder.decode(Data(field(2, bytes: document) + field(42, bytes: [1, 2, 3])))
        let decoded = try #require(index.documents.first)
        #expect(decoded.positionEncoding == 2)
        #expect(decoded.occurrences.first?.range == SCIPRange(startLine: 3, startCharacter: 4, endLine: 3, endCharacter: 9))
        #expect(decoded.occurrences.first?.enclosingRange == SCIPRange(startLine: 2, startCharacter: 0, endLine: 6, endCharacter: 1))
        #expect(decoded.occurrences.first?.isDefinition == true)
        let normalized = SemanticIndex(indexes: [index])
        #expect(normalized.documents["a.go"]?.encoding == .utf16)
        #expect(normalized.displayName(SemanticSymbolID(symbol: "x y z 1 a#", document: "a.go")) == "a")
    }

    @Test func symbolStringFallbackNamesHandleDescriptors() {
        #expect(SCIPSymbolString.fallbackName(for: "rust-analyzer cargo ra_fixture 0.1.0 shapes/impl#[Circle]area().") == "area")
        #expect(SCIPSymbolString.fallbackName(for: "rust-analyzer cargo core https://github.com/rust-lang/rust/library/core ops/arith/impl#[f64][`AddAssign<Self>`]add_assign().") == "add_assign")
        #expect(SCIPSymbolString.fallbackName(for: "scip-typescript npm pkg 1.0.0 src/`file.ts`/`weird name`.") == "weird name")
        #expect(SCIPSymbolString.fallbackName(for: "local 12") == "12")
        #expect(SCIPSymbolString.descriptorText(of: "a b  c d e f/") == "f/")
    }
}
