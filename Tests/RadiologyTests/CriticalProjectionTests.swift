import Foundation
import Testing
@testable import Radiology

struct CriticalProjectionTests {
    @Test func fixtureCallsStandOutWhileDeclarationsAndExpressionsRecede() async throws {
        let (_, index) = try SemanticIndexTests.loadFixture()
        let buffer = try SemanticIndexTests.buffer("src/lib.rs")
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let semantics = DocumentSemantics.make(document: try #require(index.documents[buffer.path]), buffer: buffer)
        let policy = CriticalityPolicy(repositoryPackages: CriticalityPolicy.repositoryPackages(in: index))
        let projection = CriticalProjection.make(semantics: semantics, buffer: buffer, syntax: syntax) { policy.classify($0, in: index) }
        func dim(_ token: String) throws -> Bool {
            let start = try #require(buffer.text.range(of: token)).lowerBound
            let byte = buffer.text.utf8.distance(from: buffer.text.startIndex, to: start)
            return projection.recededByteRanges.contains { $0.contains(byte) }
        }
        #expect(try !dim("area()"), "repository method call remains prominent")
        #expect(try dim("total_area"), "declaration names do not compete")
        #expect(try dim("Circle"), "types recede")
        #expect(try dim("for"))
        #expect(try dim("+="))
        #expect(try dim("item.area"), "receiver recedes independently of call name")
        #expect(projection.matches(buffer))
        var changed = buffer.data
        changed[0] = UInt8(ascii: "Q")
        #expect(!projection.matches(try SourceBuffer(path: buffer.path, data: changed)))
        #expect(projection.recededByteRanges == SourceProjection.normalized(projection.recededByteRanges))
    }

    @Test func onlySyntacticNamesEscapeDimmingWithIdentityBasedOrdinaryCallsExcluded() async throws {
        let source = """
        // repo() in a comment is not a call
        fn declared(value: Type) {
            let label = "unknown() 🚀 é";
            if self.field != CONSTANT { repo(value); self.field.clone(); }
            mystery::unknown::<Type>(self.field, 42)?;
            let pattern = Some(value);
            if let Some(binding) = pattern { return binding; }
            macro_name!("text");
        }
        """
        let buffer = try SourceBuffer(path: "focus.rs", data: Data(source.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let ordinary = SemanticSymbolID(symbol: "rust-analyzer cargo core . clone/Clone#clone().", document: buffer.path)
        let critical = SemanticSymbolID(symbol: "rust-analyzer cargo example 1 repo().", document: buffer.path)
        let local = SemanticSymbolID(symbol: "local 7", document: buffer.path)
        func range(_ token: String) throws -> Range<Int> {
            let found = try #require(source.range(of: token, options: .backwards))
            let lower = source.utf8.distance(from: source.startIndex, to: found.lowerBound)
            return lower..<(lower + token.utf8.count)
        }
        func occurrence(_ token: String, symbol: SemanticSymbolID) throws -> DocumentSemantics.Occurrence {
            let bytes = try range(token)
            let line = buffer.line(atByte: bytes.lowerBound) - 1
            let column = bytes.lowerBound - buffer.lineStarts[line]
            return DocumentSemantics.Occurrence(byteRange: bytes, range: SCIPRange(startLine: line, startCharacter: column, endLine: line, endCharacter: column + bytes.count), symbol: symbol, roles: 0)
        }
        // A critical mark on a field/local must not promote non-call text.
        let occurrences = try [occurrence("clone", symbol: ordinary), occurrence("repo", symbol: critical), occurrence("field", symbol: critical), occurrence("binding", symbol: local)]
        let semantics = DocumentSemantics(path: buffer.path, occurrences: occurrences.sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }, unmappedCount: 0)
        let policy = CriticalityPolicy(overrides: CriticalityOverrides(symbols: [critical.symbol: .critical]))
        let projection = CriticalProjection.make(semantics: semantics, buffer: buffer, syntax: syntax) { policy.classify($0, in: .empty) }
        func dim(_ token: String) throws -> Bool {
            let bytes = try range(token)
            return projection.recededByteRanges.contains { $0.contains(bytes.lowerBound) }
        }
        #expect(try !dim("repo"))
        #expect(try !dim("unknown::<"), "unresolved actual call stays visible without a SCIP identity")
        #expect(try !dim("macro_name"))
        #expect(try dim("clone"), "ordinary runtime call remains dim")
        for token in ["declared", "Type", "let", "if", "return", "self", "field", "CONSTANT", "42", "?", "binding", "Some(binding)", "text", "🚀", "é"] {
            #expect(try dim(token), "non-call source recedes: \(token)")
        }
        // Every prominent byte belongs to a named syntactic call; declarations,
        // patterns, strings containing call spellings, and comments never qualify.
        for byte in buffer.data.indices where !projection.recededByteRanges.contains(where: { $0.contains(byte) }) {
            #expect(syntax.callSites.contains { $0.nameByteRange?.contains(byte) == true })
        }
        // Non-ASCII source before the unknown call does not shift its TextKit boundary.
        let unknown = try range("unknown")
        let utf16 = buffer.utf16Range(forByteRange: unknown)
        #expect((source as NSString).substring(with: utf16) == "unknown")
        #expect(projection.recededByteRanges.allSatisfy { range in
            let converted = buffer.utf16Range(forByteRange: range)
            return (source as NSString).substring(with: converted).data(using: .utf8) == buffer.data.subdata(in: range)
        })
    }

    @Test func syntaxWithoutSemanticDataStillFocusesCallsAndMissingSyntaxDoesNothing() async throws {
        let buffer = try SourceBuffer(path: "unindexed.rs", data: Data("fn no_calls() { let x = 3; }\nfn next() { missing(x); }".utf8))
        let semantics = DocumentSemantics(path: buffer.path, occurrences: [], unmappedCount: 0)
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let classify: (SemanticSymbolID) -> CriticalityClassification = { _ in Issue.record("unresolved calls must not be classified"); return CriticalityPolicy().classify(SemanticSymbolID(symbol: "local 0", document: buffer.path), in: .empty) }
        let projection = CriticalProjection.make(semantics: semantics, buffer: buffer, syntax: syntax, classify: classify)
        let name = try #require(syntax.callSites.first?.nameByteRange)
        #expect(projection.recededByteRanges == [0..<name.lowerBound, name.upperBound..<buffer.data.count])
        #expect(CriticalProjection.make(semantics: semantics, buffer: buffer, syntax: nil, classify: classify).recededByteRanges.isEmpty)
        let other = try SourceBuffer(path: "other.rs", data: buffer.data)
        #expect(CriticalProjection.make(semantics: semantics, buffer: other, syntax: syntax, classify: classify).recededByteRanges.isEmpty)
    }
}
