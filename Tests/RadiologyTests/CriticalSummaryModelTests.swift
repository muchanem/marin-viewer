import Foundation
import Testing
@testable import Radiology

/// Source gutter/hover work through AppModel: sidebar context is independent
/// of source mode, caret movement schedules nothing, marks refresh counts,
/// stale results are dropped, and hover opens/closes by dwell and grace.
@MainActor
struct CriticalSummaryModelTests {
    private func makeModel() throws -> (AppModel, URL, URL) {
        let root = try IndexingTests.temporaryRepository()
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fake = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(IndexingTests.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot.appending(path: "tools")))
        let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
        let lens = CriticalLensModel(store: CriticalityOverrideStore(directory: cacheRoot.appending(path: "overrides")))
        let model = AppModel(preferences: preferences, semantics: SemanticModel(service: service), criticalLens: lens)
        model.criticalSummaries.hoverDwell = .milliseconds(20)
        model.criticalSummaries.hoverGrace = .milliseconds(40)
        return (model, root, cacheRoot)
    }

    private func openLib(_ model: AppModel, root: URL) async throws -> SourceBuffer {
        model.openRepository(root)
        try await IndexingTests.waitUntil { model.semantics.status == .current }
        model.openFile("src/lib.rs")
        try await IndexingTests.waitUntil { model.semantics.documentSemantics?.path == "src/lib.rs" && model.syntax?.path == "src/lib.rs" }
        return try #require(model.source)
    }

    private struct NavigationState: Equatable {
        let path: String?, target: Radiology.SourceLocation?, revision: Int, history: [Radiology.SourceLocation], index: Int
        @MainActor init(_ model: AppModel) {
            path = model.source?.path; target = model.navigationTarget; revision = model.navigationRevision
            history = model.history.entries; index = model.history.index
        }
    }

    @Test func modeKeepsContextReferencesStableAndCaretRequestsNoSummaries() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let lib = try await openLib(model, root: root)
        let summaries = model.criticalSummaries
        model.caretMoved(to: lib.byteOffset(line: 8, column: 21))
        model.findReferencesAtCaret()
        try await IndexingTests.waitUntil { if case .loaded = model.context.references { true } else { false } }
        let loaded: ReferenceResults? = if case .loaded(let results) = model.context.references { results } else { nil }
        let results = try #require(loaded)
        let hit = try #require(results.groups.flatMap(\.hits).first)
        model.context.selectedReferenceID = hit.id
        model.context.setReference(hit.id, expanded: true)
        model.context.isDeclarationExpanded = true
        model.context.isDefinitionExpanded = true
        let declaration = model.context.declaration?.identity
        let definition = model.context.underCaret?.identity
        let references = model.context.references
        let before = NavigationState(model)
        let caret = model.currentCaretLocation

        model.sourceMode = .critical
        try await IndexingTests.waitUntil { !summaries.isAnnotating && !summaries.foldAnnotations.isEmpty }
        #expect(model.context.declaration?.identity == declaration)
        #expect(model.context.underCaret?.identity == definition)
        #expect(model.context.references == references)
        #expect(model.context.selectedReferenceID == hit.id && model.canCommitSelectedRow)
        #expect(model.context.isReferenceExpanded(hit.id))
        #expect(model.context.isDeclarationExpanded && model.context.isDefinitionExpanded)
        #expect(NavigationState(model) == before && model.currentCaretLocation == caret)
        let builds = await summaries.worker.summaryBuildCount
        let annotations = summaries.annotationRunCount
        for (line, column) in [(7, 9), (8, 21), (8, 23), (6, 15)] {
            model.caretMoved(to: lib.byteOffset(line: line, column: column))
        }
        try await Task.sleep(for: .milliseconds(80))
        #expect(await summaries.worker.summaryBuildCount == builds, "sidebar caret identities no longer summarize callables")
        #expect(summaries.annotationRunCount == annotations)
        #expect(summaries.hoverRequestCount == 0)
        model.sourceMode = .normal
        #expect(summaries.foldAnnotations.isEmpty)
        #expect(model.context.references == references && model.context.selectedReferenceID == hit.id)
        model.sourceMode = .critical
        try await IndexingTests.waitUntil { !summaries.isAnnotating && !summaries.foldAnnotations.isEmpty }
        model.commitSelectedReference()
        try await IndexingTests.waitUntil { model.navigationRevision != before.revision }
        #expect(model.navigationTarget?.path == hit.location.path)
        model.goBack()
        try await IndexingTests.waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget == Radiology.SourceLocation(path: "src/lib.rs", byteOffset: lib.byteOffset(line: 6, column: 15)))
    }

    @Test func gutterMarksRefreshAndStaleWorkClearsOnModeAndFileChanges() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let lib = try await openLib(model, root: root)
        let summaries = model.criticalSummaries
        model.sourceMode = .critical
        model.sourceMode = .normal
        try await Task.sleep(for: .milliseconds(80))
        #expect(summaries.foldAnnotations.isEmpty)
        model.sourceMode = .critical
        let syntax = try #require(model.syntax)
        let total = try #require(syntax.symbols.first { $0.name == "total_area" })
        let fold = try #require(CriticalSummaryModel.bodyFold(of: total, in: syntax))
        try await IndexingTests.waitUntil { summaries.foldAnnotations[fold.id] != nil }
        #expect(summaries.foldAnnotations[fold.id] == CountAnnotation(count: 1, completeness: .proven))
        let area = try #require(model.semantics.target(at: lib.byteOffset(line: 8, column: 21)))
        model.criticalLens.setSymbol(area.symbol.symbol, to: .ordinary)
        try await IndexingTests.waitUntil { summaries.foldAnnotations[fold.id]?.isProvenZero == true }
        model.criticalLens.setSymbol(area.symbol.symbol, to: nil)
        try await IndexingTests.waitUntil { summaries.foldAnnotations[fold.id]?.count == 1 }
        model.openFile("Cargo.toml")
        #expect(summaries.foldAnnotations.isEmpty)
        try await IndexingTests.waitUntil { model.source?.path == "Cargo.toml" }
        model.openRepository(root)
        #expect(summaries.foldAnnotations.isEmpty && summaries.hover == nil)
    }

    @Test func declarationsWithoutSourceFoldsScheduleNoAnnotationWork() async throws {
        let buffer = try SourceBuffer(path: "abstract.rs", data: Data("trait API { fn operation(&self); }".utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let callables = syntax.symbols.filter { SyntaxSnapshot.callableKinds.contains($0.kind) }
        #expect(!callables.isEmpty)
        #expect(callables.allSatisfy { CriticalSummaryModel.bodyFold(of: $0, in: syntax) == nil })
        let summaries = CriticalSummaryModel()
        let inputs = ContextInputs(root: URL(filePath: "/tmp"), buffer: buffer, sourceIdentity: SourceContentIdentity(buffer.data),
                                   syntax: syntax, caretByte: 0, index: .empty, indexRevision: 0,
                                   documentSemantics: DocumentSemantics(path: buffer.path, occurrences: [], unmappedCount: 0), documentRevision: 0)
        summaries.update(inputs, mode: .critical, policy: CriticalityPolicy(), policyRevision: 0)
        try await Task.sleep(for: .milliseconds(40))
        #expect(summaries.annotationRunCount == 0 && !summaries.isAnnotating)
        #expect(await summaries.worker.summaryBuildCount == 0, "outline-only declarations have no consumer")
        #expect(summaries.foldAnnotations.isEmpty && summaries.hoverRequestCount == 0)
    }

    @Test func hoverOpensAfterDwellAndClosesByGraceOrEvents() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let lib = try await openLib(model, root: root)
        let summaries = model.criticalSummaries
        let areaByte = lib.byteOffset(line: 8, column: 20)
        model.pointerOverSource(at: areaByte)
        #expect(summaries.hover == nil, "Normal mode never hovers")
        model.sourceMode = .critical
        model.caretMoved(to: areaByte + 2)
        let before = NavigationState(model)
        let caretBefore = model.currentCaretLocation
        model.pointerOverSource(at: lib.byteOffset(line: 8, column: 10))   // `sum`, a local
        try await Task.sleep(for: .milliseconds(60))
        #expect(summaries.hover == nil, "locals and non-callables never open a popover")
        model.pointerOverSource(at: areaByte)
        #expect(summaries.hover == nil, "not before the dwell")
        try await IndexingTests.waitUntil { summaries.hover?.phase.frontier != nil }
        let hover = try #require(summaries.hover)
        #expect(hover.displayName == "area" && hover.definition?.path == "src/shapes.rs")
        #expect(hover.byteRange == lib.byteOffset(line: 8, column: 20)..<lib.byteOffset(line: 8, column: 24))
        #expect(NavigationState(model) == before, "hover moves nothing")
        #expect(model.currentCaretLocation == caretBefore, "hover never moves the caret")
        // Still on the token: stays. Into the popover: stays. Off both: closes after the grace.
        model.pointerOverSource(at: areaByte + 2)
        try await Task.sleep(for: .milliseconds(80))
        #expect(summaries.hover?.id == hover.id)
        model.pointerOverSource(at: nil)
        model.hoverPopoverHovered(true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(summaries.hover?.id == hover.id, "pointer moved from the source into the popover")
        // Crossing a different callable during entry must not replace the open
        // popup; native tracking owns it until the pointer leaves.
        model.pointerOverSource(at: lib.byteOffset(line: 5, column: 8))
        try await Task.sleep(for: .milliseconds(80))
        #expect(summaries.hover?.id == hover.id)
        model.hoverPopoverHovered(false)
        try await IndexingTests.waitUntil { summaries.hover == nil }
        // Re-hover, then a click/scroll/key dismisses at once; a mode change too.
        model.pointerOverSource(at: areaByte)
        try await IndexingTests.waitUntil { summaries.hover != nil }
        model.dismissHoverSummary()
        #expect(summaries.hover == nil)
        model.pointerOverSource(at: areaByte)
        try await IndexingTests.waitUntil { summaries.hover != nil }
        model.sourceMode = .normal
        #expect(summaries.hover == nil)
        // A pending dwell that is cancelled never presents.
        model.sourceMode = .critical
        model.pointerOverSource(at: areaByte)
        model.pointerOverSource(at: nil)
        try await Task.sleep(for: .milliseconds(80))
        #expect(summaries.hover == nil)
        // A critical external callable gets an honest no-body presentation; plumbing does not.
        var overrides = CriticalityOverrides()
        let plusEquals = try #require(model.semantics.target(at: lib.byteOffset(line: 8, column: 12)))
        #expect(!plusEquals.symbol.isCallable(in: model.semantics.index) || plusEquals.symbol.symbol.hasSuffix("()."))
        overrides.setSymbol(plusEquals.symbol.symbol, to: .critical)
        model.criticalLens.setSymbol(plusEquals.symbol.symbol, to: .critical)
        model.pointerOverSource(at: lib.byteOffset(line: 8, column: 12))
        try await IndexingTests.waitUntil { summaries.hover != nil }
        #expect(summaries.hover?.definition == nil)
        #expect(summaries.hover?.phase.frontier?.coverage == .noBody(.external))
        #expect(NavigationState(model) == before)
        #expect(model.currentCaretLocation == caretBefore)
        // The actual hovered destination uses exact-caret navigation and Back.
        model.activateCriticalDestination(hover.definition, name: hover.displayName)
        try await IndexingTests.waitUntil { model.source?.path == "src/shapes.rs" }
        model.goBack()
        try await IndexingTests.waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget == caretBefore)
    }
}
