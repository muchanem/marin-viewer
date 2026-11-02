import Foundation
import Testing
@testable import Radiology

/// End-to-end through `AppModel`: open a repository with no prebuilt data, let
/// the (fake) indexer generate, jump across files, and come back exactly.
@MainActor
struct SemanticNavigationTests {
    private func waitUntil(_ timeout: Duration = .seconds(30), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition(), "timed out")
    }

    private func makeModel() throws -> (AppModel, URL, URL) {
        let root = try IndexingTests.temporaryRepository()
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fake = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(IndexingTests.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot.appending(path: "tools")))
        let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
        return (AppModel(preferences: preferences, semantics: SemanticModel(service: service)), root, cacheRoot)
    }

    @Test func commandClickJumpsAcrossFilesAndBackReturnsToTheExactByte() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        model.openRepository(root)
        try await waitUntil { !model.isOpening }
        try await waitUntil { model.semantics.status == .current }
        model.openFile("src/lib.rs")
        try await waitUntil { model.source != nil && model.semantics.documentSemantics != nil }
        let lib = try #require(model.source)
        // Scroll somewhere, then ⌘-click `Circle` on line 5: Back must return to the click byte, not the scroll position.
        model.updatePosition(path: "src/lib.rs", byteOffset: lib.byteOffset(line: 9), line: 9)
        let clickByte = lib.byteOffset(line: 5, column: 29)
        #expect(model.semantics.target(at: clickByte)?.displayName == "Circle")
        model.goToDefinition(at: clickByte)
        try await waitUntil { model.source?.path == "src/shapes.rs" }
        let shapes = try #require(model.source)
        #expect(model.navigationTarget == SourceLocation(path: "src/shapes.rs", byteOffset: shapes.byteOffset(line: 1, column: 11)))
        #expect(model.jumpHighlightTarget == model.navigationTarget)
        #expect(model.currentLine == 1)
        try await waitUntil { model.semantics.documentSemantics?.path == "src/shapes.rs" }
        #expect(model.semantics.caretTarget?.displayName == "Circle")
        #expect(model.semantics.caretTarget?.isOnDefinition == true)
        model.goBack()
        try await waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget == SourceLocation(path: "src/lib.rs", byteOffset: clickByte))
        #expect(model.currentLine == 5)
        model.goForward()
        try await waitUntil { model.source?.path == "src/shapes.rs" }
        #expect(model.navigationTarget?.byteOffset == shapes.byteOffset(line: 1, column: 11))

        // A symbol defined outside the repository is reported, not guessed.
        model.goBack()
        try await waitUntil { model.source?.path == "src/lib.rs" }
        try await waitUntil { model.semantics.documentSemantics?.path == "src/lib.rs" }
        model.goToDefinition(at: lib.byteOffset(line: 8, column: 12))
        try await waitUntil { model.semantics.navigationError != nil }
        #expect(model.semantics.navigationError?.contains("outside this repository") == true)
        #expect(model.source?.path == "src/lib.rs")
    }

    @Test func referencesAndSymbolSearchUseTheGeneratedIndex() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        model.openRepository(root)
        try await waitUntil { model.semantics.status == .current }
        model.openFile("src/shapes.rs")
        try await waitUntil { model.semantics.documentSemantics != nil }
        let shapes = try #require(model.source)
        model.findReferences(at: shapes.byteOffset(line: 1, column: 12))
        #expect(model.context.explicitReferences?.displayName == "Circle")
        try await waitUntil { if case .loaded = model.context.references { true } else { false } }
        guard case .loaded(let references) = model.context.references else { return }
        #expect(references.displayName == "Circle")
        #expect(references.groups.map(\.path) == ["src/lib.rs", "src/shapes.rs"])
        #expect(references.total == 5)
        #expect(references.referenceCount == 4, "the definition is listed and labelled but not counted as a reference")
        #expect(references.definitionCount == 1)
        #expect(references.groups[1].hits.first?.isDefinition == true)
        #expect(references.groups[0].hits.map(\.line) == [2, 5])
        #expect(references.groups[0].hits.first?.lineText == "pub use shapes::Circle;")
        let hit = try #require(references.groups[0].hits.last)
        model.navigateSemantically(from: model.currentCaretLocation!, to: hit.location)
        try await waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget?.byteOffset == hit.byteRange.lowerBound)

        model.semantics.searchSymbols("circ")
        try await waitUntil { !model.semantics.symbolMatches.isEmpty }
        #expect(model.semantics.symbolMatches.first?.entry.name == "Circle")
        #expect(model.semantics.symbolMatches.first?.entry.kind.name == "Struct")
        model.navigate(toDefinition: model.semantics.symbolMatches[0].entry.position)
        try await waitUntil { model.source?.path == "src/shapes.rs" }
        #expect(model.navigationTarget?.byteOffset == model.source?.byteOffset(line: 1, column: 11))
    }

    @Test func switchingRepositoriesDropsTheOldIndexAndTargets() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        model.openRepository(root)
        try await waitUntil { model.semantics.status == .current }
        model.openFile("src/lib.rs")
        try await waitUntil { model.semantics.documentSemantics != nil }
        let revision = model.semantics.indexRevision
        let plain = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        try Data("let x = 1\n".utf8).write(to: plain.appending(path: "A.swift"))
        model.openRepository(plain)
        try await waitUntil { !model.isOpening }
        // `.noIndex("Checking the repository…")` is set synchronously on open;
        // wait for the service's real publication, not that placeholder.
        try await waitUntil {
            if case .noIndex(let reason) = model.semantics.status { reason != "Checking the repository…" } else { false }
        }
        #expect(!model.semantics.hasIndex)
        #expect(model.semantics.documentSemantics == nil)
        #expect(model.semantics.caretTarget == nil)
        #expect(model.semantics.indexRevision > revision)
        #expect(model.semantics.unsupportedLanguages == ["Swift"])
    }

    @Test func ordinarySemanticSelectionClearsAcrossWhitespaceAndFiles() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        model.openRepository(root)
        try await waitUntil { model.semantics.status == .current }
        model.openFile("src/shapes.rs")
        try await waitUntil { model.semantics.documentSemantics != nil }
        let shapes = try #require(model.source)

        model.semantics.selectOccurrences(at: shapes.byteOffset(line: 6, column: 48))
        let selected = try #require(model.semantics.occurrenceSelection)
        #expect(selected.symbol.symbol.hasSuffix("Circle#radius."))
        #expect(selected.byteRanges.count == 3)

        model.semantics.selectOccurrences(at: shapes.byteOffset(line: 4, column: 0))
        #expect(model.semantics.occurrenceSelection == nil)
        model.semantics.selectOccurrences(at: shapes.byteOffset(line: 6, column: 48))
        #expect(model.semantics.occurrenceSelection != nil)

        model.openFile("src/lib.rs")
        try await waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.semantics.occurrenceSelection == nil, "a file change must clear stale byte ranges immediately")
    }
}
