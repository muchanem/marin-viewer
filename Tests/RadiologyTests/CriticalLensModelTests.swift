import Foundation
import Testing
@testable import Radiology

/// End to end through `AppModel` with the fake indexer: switching modes
/// publishes and clears the projection without touching navigation, caret
/// moves cost nothing, overrides recompute, and the projection follows the
/// bytes, the index, and the structure.
@MainActor
struct CriticalLensModelTests {
    private func makeModel() throws -> (AppModel, URL, URL) {
        let root = try IndexingTests.temporaryRepository()
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fake = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(IndexingTests.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot.appending(path: "tools")))
        let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
        let lens = CriticalLensModel(store: CriticalityOverrideStore(directory: cacheRoot.appending(path: "overrides")))
        return (AppModel(preferences: preferences, semantics: SemanticModel(service: service), criticalLens: lens), root, cacheRoot)
    }

    @Test func modeTogglesProjectionWithoutTouchingNavigation() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        model.openRepository(root)
        try await IndexingTests.waitUntil { model.semantics.status == .current }
        model.openFile("src/shapes.rs")
        try await IndexingTests.waitUntil { model.semantics.documentSemantics?.path == "src/shapes.rs" && model.syntax?.path == "src/shapes.rs" }
        let shapes = try #require(model.source)
        let piByte = try #require(shapes.text.range(of: "PI").map { shapes.text.utf8.distance(from: shapes.text.startIndex, to: $0.lowerBound) })
        model.caretMoved(to: piByte)
        #expect(model.criticalLens.projection == nil, "Normal mode has no projection")
        let canGoBack = model.history.canGoBack
        let historyCurrent = model.history.current
        let caret = model.currentCaretLocation
        let target = model.navigationTarget
        let revision = model.navigationRevision

        model.sourceMode = .critical
        try await IndexingTests.waitUntil { model.criticalLens.projection != nil }
        let projection = try #require(model.criticalLens.projection)
        #expect(projection.matches(shapes))
        #expect(projection.recededByteRanges.contains { $0.contains(piByte) })
        #expect(model.history.canGoBack == canGoBack && model.history.current == historyCurrent && model.currentCaretLocation == caret
                && model.navigationTarget == target && model.navigationRevision == revision, "a lens never navigates")
        let requests = model.criticalLens.projectionRequestCount
        for offset in 0..<5 { model.caretMoved(to: piByte + offset) }
        #expect(model.criticalLens.projectionRequestCount == requests, "caret movement requests nothing")
        #expect(model.criticalLens.projection?.id == projection.id)

        // Marks still persist, but non-call constants remain dim even when critical.
        let piTarget = try #require(model.semantics.target(at: piByte))
        #expect(model.criticalityMenu(at: piByte)?.packageName == "core", "std::f64::consts::PI resolves to core")
        #expect(model.criticalityMenu(at: piByte)?.packageKey == "rust-analyzer cargo core")
        #expect(model.criticalityMenu(at: piByte)?.builtIn.criticality == .ordinary)
        model.criticalLens.setSymbol(piTarget.symbol.symbol, to: .critical)
        try await IndexingTests.waitUntil { model.criticalLens.projection?.id != projection.id }
        #expect(model.criticalLens.projection?.recededByteRanges.contains { $0.contains(piByte) } == true)
        #expect(model.criticalityMenu(at: piByte)?.symbolDecision == .critical)
        let marked = model.criticalLens.projection?.id
        model.criticalLens.setSymbol(piTarget.symbol.symbol, to: nil)
        try await IndexingTests.waitUntil { model.criticalLens.projection?.id != marked }
        #expect(model.criticalLens.projection?.recededByteRanges.contains { $0.contains(piByte) } == true)
        // The decision file lives in the store's directory, not the repository.
        let beforePackage = model.criticalLens.projection?.id
        model.criticalLens.setPackage("rust-analyzer cargo core", to: .critical)
        try await IndexingTests.waitUntil { model.criticalLens.projection?.id != beforePackage }
        #expect(model.criticalLens.projection?.recededByteRanges.contains { $0.contains(piByte) } == true)
        let overridesDirectory = cacheRoot.appending(path: "overrides")
        try await IndexingTests.waitUntil { (try? FileManager.default.contentsOfDirectory(atPath: overridesDirectory.path))?.isEmpty == false }
        #expect(model.criticalLens.overrideError == nil)

        // Normal clears; Critical again reuses the cached projection for the same bytes/index/policy.
        let builds = await model.criticalLens.worker.projectionBuildCount
        model.sourceMode = .normal
        #expect(model.criticalLens.projection == nil)
        model.sourceMode = .critical
        try await IndexingTests.waitUntil { model.criticalLens.projection != nil }
        #expect(await model.criticalLens.worker.projectionBuildCount == builds, "same inputs, cached projection")

        // A file without call syntax has no projection; returning restores one.
        model.openFile("Cargo.toml")
        try await IndexingTests.waitUntil { model.source?.path == "Cargo.toml" }
        #expect(model.criticalLens.projection == nil)
        model.openFile("src/shapes.rs")
        try await IndexingTests.waitUntil { model.criticalLens.projection?.path == "src/shapes.rs" }

        // Reopening the repository reloads persisted decisions.
        model.openRepository(root)
        #expect(model.criticalLens.projection == nil, "repository change clears at once")
        try await IndexingTests.waitUntil { model.criticalLens.overrides.packages["rust-analyzer cargo core"] == .critical }
    }

    @Test func editsBeforeLoadAreKeptAndSavesStayOrdered() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-overrides-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = FileManager.default.temporaryDirectory.appending(path: "repo-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // A persisted decision from an earlier session.
        var persisted = CriticalityOverrides()
        persisted.setPackage("rust-analyzer cargo std", to: .ordinary)
        persisted.setSymbol("rust-analyzer cargo core . a/b().", to: .critical)
        try await CriticalityOverrideStore(directory: directory).save(persisted, for: root, revision: 1)

        let slow = CriticalityOverrideStore(directory: directory, artificialLoadDelay: .milliseconds(150))
        let lens = CriticalLensModel(store: slow)
        lens.repositoryOpened(root)
        #expect(lens.isLoadingOverrides)
        // The reader decides before the file has loaded: std becomes critical, and a new symbol is marked.
        lens.setPackage("rust-analyzer cargo std", to: .critical)
        lens.setSymbol("rust-analyzer cargo serde_json 1 x/y().", to: .ordinary)
        #expect(lens.overrides.packages["rust-analyzer cargo std"] == .critical, "applies to the session at once")
        try await IndexingTests.waitUntil { !lens.isLoadingOverrides }
        // Loaded decisions arrive, but the newer edits win over the stale file.
        #expect(lens.overrides.packages["rust-analyzer cargo std"] == .critical)
        #expect(lens.overrides.symbols["rust-analyzer cargo core . a/b()."] == .critical, "untouched persisted decision survives")
        #expect(lens.overrides.symbols["rust-analyzer cargo serde_json 1 x/y()."] == .ordinary)
        await lens.flushSaves()
        #expect(await slow.load(for: root) == CriticalityOverrides(repositoryRoot: CriticalityOverrideStore.canonicalPath(root),
                                                                    symbols: lens.overrides.symbols, packages: lens.overrides.packages))

        // Rapid edits: the disk ends with the last snapshot, never an older one.
        for step in 0..<25 { lens.setSymbol("rust-analyzer cargo core . rapid/\(step)().", to: step % 2 == 0 ? .critical : .ordinary) }
        lens.setPackage("rust-analyzer cargo std", to: nil)
        await lens.flushSaves()
        let final = await slow.load(for: root)
        #expect(final.symbols == lens.overrides.symbols)
        #expect(final.packages == lens.overrides.packages)
        #expect(final.packages["rust-analyzer cargo std"] == nil)
        #expect(lens.overrideError == nil)
    }

    @Test func unindexedFileProjectsSyntacticCallsWithoutCreatingTargets() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        try "fn extra() { missing(42); }".write(to: root.appending(path: "extra.rs"), atomically: true, encoding: .utf8)
        model.openRepository(root)
        try await IndexingTests.waitUntil { !model.isOpening }
        model.openFile("extra.rs")
        model.sourceMode = .critical
        try await IndexingTests.waitUntil { model.criticalLens.projection?.path == "extra.rs" }
        let buffer = try #require(model.source)
        let syntax = try #require(model.syntax)
        let name = try #require(syntax.callSites.first?.nameByteRange)
        let projection = try #require(model.criticalLens.projection)
        #expect(!projection.recededByteRanges.contains { $0.overlaps(name) })
        #expect(projection.recededByteRanges.first?.lowerBound == 0)
        #expect(model.semantics.target(at: name.lowerBound) == nil)
        #expect(projection.matches(buffer))
    }

    @Test func projectionUsesCallSyntaxAndExactBytes() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        model.sourceMode = .critical
        model.openRepository(root)
        try await IndexingTests.waitUntil { !model.isOpening }
        model.openFile("src/lib.rs")
        try await IndexingTests.waitUntil { model.semantics.status == .current && model.semantics.documentSemantics?.path == "src/lib.rs" && model.syntax?.path == "src/lib.rs" }
        try await IndexingTests.waitUntil { model.criticalLens.projection?.path == "src/lib.rs" }
        let projection = try #require(model.criticalLens.projection)
        let lib = try #require(model.source)
        #expect(projection.matches(lib))
        // Non-call source, including declaration syntax, is now receded.
        #expect(projection.recededByteRanges.first?.lowerBound == 0)
        #expect(projection.recededByteRanges.allSatisfy { $0.upperBound <= lib.data.count })
    }
}
