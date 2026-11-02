import Foundation
import Testing
@testable import Radiology

struct TraitImplementationTests {
    static let fixtureRoot = Bundle.module.resourceURL!.appending(path: "Fixtures/scip-rust-traits")

    static func fixture() throws -> (root: URL, cache: URL, raw: SCIPIndex, index: SemanticIndex) {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-trait-tests-\(UUID().uuidString)")
        let cache = root.appending(path: "cache")
        try FileManager.default.copyItem(at: fixtureRoot, to: root)
        let raw = try SCIPDecoder.decode(Data(contentsOf: root.appending(path: "index.scip")))
        return (root.resolvingSymlinksInPath(), cache, raw, SemanticIndex(indexes: [raw]))
    }

    static func id(_ suffix: String, index: SemanticIndex) throws -> SemanticSymbolID {
        try #require(index.symbols.keys.first { $0.symbol.hasSuffix(suffix) })
    }

    static func enriched(root: URL, cache: URL, index: SemanticIndex) async throws -> SemanticIndex {
        let catalog = try await TraitImplementationIndexer().build(index: index, root: root, cacheDirectory: cache,
            repositoryPaths: ["src/lib.rs", "src/implementations.rs"])
        return SemanticIndex(base: index, traitImplementations: catalog)
    }

    @Test func realRustIndexResolvesAliasesQualifiedBlanketAndNegativeImpls() async throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let index = try await Self.enriched(root: f.root, cache: f.cache, index: f.index)
        let left = try Self.id("left/Render#", index: index)
        let right = try Self.id("right/Render#", index: index)
        let marker = try Self.id("left/Marker#", index: index)
        let empty = try Self.id("left/Empty#", index: index)
        let rows = try #require(index.traitImplementations.byTrait[left])
        #expect(rows.map(\.targetType) == ["Alpha", "Beta", "Wrapper<T>"])
        #expect(rows.first?.signature == "impl Alias for Alpha")
        #expect(rows.last?.signature.contains("where T: Copy") == true)
        #expect(rows.allSatisfy { !$0.isNegative })
        #expect(index.traitImplementations.byTrait[right]?.map(\.targetType) == ["Other"])
        #expect(index.traitImplementations.byTrait[marker]?.first?.isNegative == true)
        #expect(index.traitImplementations.byTrait[empty] == nil)
        #expect(index.traitImplementations.unresolvedCount == 0)
        #expect(!index.traitImplementations.hasGaps)
        #expect(index.traitImplementations.parsedDocumentCount == 2)
        #expect(f.raw.documents.flatMap(\.symbols).allSatisfy { $0.relationships.isEmpty })
        // Merged duplicate contributions do not duplicate an explicit block.
        let merged = SemanticIndex(indexes: [f.raw, f.raw])
        let duplicated = try await Self.enriched(root: f.root, cache: f.cache, index: merged)
        #expect(duplicated.traitImplementations.byTrait[left]?.count == 3)
    }

    @Test func persistentCacheInvalidatesForSourceAndSemanticIdentity() async throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        _ = try await Self.enriched(root: f.root, cache: f.cache, index: f.index)
        // A fresh actor proves this is persisted, not an in-memory shortcut.
        let warm = try await Self.enriched(root: f.root, cache: f.cache, index: f.index)
        #expect(warm.traitImplementations.parsedDocumentCount == 0)
        #expect(warm.traitImplementations.cachedDocumentCount == 2)
        let sourceURL = f.root.appending(path: "src/implementations.rs")
        let bytes = try Data(contentsOf: sourceURL)
        try (bytes + Data("\n// changed bytes\n".utf8)).write(to: sourceURL)
        let changed = try await Self.enriched(root: f.root, cache: f.cache, index: f.index)
        #expect(changed.traitImplementations.parsedDocumentCount == 1)
        #expect(changed.traitImplementations.cachedDocumentCount == 1)
        var raw = f.raw
        let right = try Self.id("right/Render#", index: f.index)
        let doc = try #require(raw.documents.firstIndex { $0.relativePath == "src/implementations.rs" })
        let alias = try #require(raw.documents[doc].occurrences.firstIndex {
            $0.range?.startLine == 1 && $0.symbol.hasSuffix("left/Render#")
        })
        raw.documents[doc].occurrences[alias].symbol = right.symbol
        let remapped = try await Self.enriched(root: f.root, cache: f.cache, index: SemanticIndex(indexes: [raw]))
        #expect(remapped.traitImplementations.parsedDocumentCount == 1)
        #expect(remapped.traitImplementations.byTrait[right]?.map(\.targetType) == ["Alpha", "Other"])
        // Corrupt derived cache never blocks semantic navigation or enrichment.
        try Data("corrupt".utf8).write(to: f.cache.appending(path: "rust-trait-implementations.json"))
        let recovered = try await Self.enriched(root: f.root, cache: f.cache, index: f.index)
        #expect(recovered.traitImplementations.parsedDocumentCount == 2)
    }

    @Test func excludesUntrustedCoordinatesAndReportsCoverageGaps() async throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let indexer = TraitImplementationIndexer()
        let excluded = try await indexer.build(index: f.index, root: f.root, cacheDirectory: f.cache,
            repositoryPaths: ["src/lib.rs", "src/implementations.rs", "src/inactive.rs"],
            excludedPaths: ["src/implementations.rs"])
        #expect(excluded.byTrait.isEmpty)
        #expect(excluded.excludedPaths == ["src/implementations.rs"])
        #expect(excluded.unindexedFileCount == 1 && excluded.hasGaps)
        let mismatch = try await indexer.build(index: f.index, root: f.root, cacheDirectory: f.cache,
            repositoryPaths: [], expectedBlobs: ["src/lib.rs": "wrong", "src/implementations.rs": "wrong"])
        #expect(mismatch.byTrait.isEmpty && mismatch.excludedPaths.count == 2)
        var raw = f.raw
        let doc = try #require(raw.documents.firstIndex { $0.relativePath == "src/implementations.rs" })
        raw.documents[doc].occurrences.removeAll { $0.symbol.hasSuffix("left/Render#") }
        let unresolved = try await Self.enriched(root: f.root, cache: f.cache, index: SemanticIndex(indexes: [raw]))
        #expect(unresolved.traitImplementations.unresolvedCount == 3)
        #expect(unresolved.traitImplementations.hasGaps)
        try FileManager.default.removeItem(at: f.root.appending(path: "src/implementations.rs"))
        let missing = try await Self.enriched(root: f.root, cache: f.cache, index: f.index)
        #expect(missing.traitImplementations.unreadablePaths == ["src/implementations.rs"])
    }

    @Test func syntaxExcludesBoundsArgumentsCommentsAndMacroTokens() async throws {
        let source = """
        trait A<T> {}
        trait B {}
        // impl A<B> for Pretend {}
        impl<T: B> A<T> for Wrapper<T> where T: B {}
        impl<T: A<B>> Wrapper<T> { fn f() {} }
        macro_rules! generated { () => { impl A<B> for Generated {} } }
        impl !B for Negative {}
        unsafe impl crate::A<dyn B> for Concrete {}
        """
        let buffer = try SourceBuffer(path: "impls.rs", data: Data(source.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        #expect(!syntax.hasParseErrors)
        #expect(syntax.rustTraitImpls.map(\.targetType) == ["Wrapper<T>", "Negative", "Concrete"])
        #expect(syntax.rustTraitImpls.map { String(decoding: buffer.data[$0.traitNameRange], as: UTF8.self) } == ["A", "B", "A"])
        #expect(syntax.rustTraitImpls[1].isNegative)
        #expect(syntax.rustTraitImpls[2].signature.hasPrefix("unsafe impl"))
    }

    @Test func navigationRejectsChangedSourceEvenAtSameLength() async throws {
        let f = try Self.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let index = try await Self.enriched(root: f.root, cache: f.cache, index: f.index)
        let id = try Self.id("left/Render#", index: index)
        let item = try #require(index.traitImplementations.byTrait[id]?.first)
        let worker = TraitImplementationWorker()
        #expect(try await worker.resolve(item, root: f.root) == item.location)
        let url = f.root.appending(path: item.path)
        let source = try String(contentsOf: url, encoding: .utf8)
        try source.replacingOccurrences(of: "Alpha", with: "Gamma").write(to: url, atomically: true, encoding: .utf8)
        await #expect(throws: BrowserError.self) { try await worker.resolve(item, root: f.root) }
    }
}
