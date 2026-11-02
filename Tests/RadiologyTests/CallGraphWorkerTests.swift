import Foundation
import Testing
@testable import Radiology

/// Call sites resolved to SCIP identities on the real fixture index, bodies
/// located across files, and policy changes flowing into frontiers.
struct CallGraphWorkerTests {
    static func configuration(root: URL, index: SemanticIndex, overrides: CriticalityOverrides = CriticalityOverrides(), revision: Int = 1) -> CallGraphWorker.Configuration {
        CallGraphWorker.Configuration(root: root, index: index, indexRevision: 1,
                                      policy: CriticalityPolicy(repositoryPackages: CriticalityPolicy.repositoryPackages(in: index), overrides: overrides),
                                      policyRevision: revision)
    }

    @Test func resolvesSitesLocatesBodiesAndHonorsMarks() async throws {
        let f = try await ContextModelTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let worker = CallGraphWorker()
        await worker.configure(Self.configuration(root: f.root, index: f.index))
        let total = try #require(f.libSyntax.symbols.first { $0.name == "total_area" })
        let semantics = DocumentSemantics.make(document: try #require(f.index.documents["src/lib.rs"]), buffer: f.lib)
        guard case .defines(let totalID) = DeclarationContext.link(for: total, in: semantics) else { Issue.record("total_area not linked"); return }
        let frontier = await worker.frontier(in: f.lib, syntax: f.libSyntax, semantics: semantics, owner: total.byteRange,
                                             callable: totalID, hasBody: true)
        #expect(frontier.summary.calls.map(\.displayName) == ["area"])
        #expect(frontier.summary.calls[0].classification == .init(criticality: .critical, reason: .repositoryDefinition))
        #expect(frontier.summary.calls[0].definition?.path == "src/shapes.rs")
        #expect(frontier.summary.calls[0].siteCount == 1)
        #expect(frontier.coverage == .complete)
        #expect(frontier.reachableCriticalCount == 1)
        #expect(frontier.statusLine == "1 direct · complete")

        // `area` in shapes.rs: body located across files, no calls, proven zero.
        let areaFrontier = await worker.frontier(of: frontier.summary.calls[0].callee)
        #expect(areaFrontier.summary.body?.path == "src/shapes.rs")
        #expect(areaFrontier.summary.calls.isEmpty)
        #expect(areaFrontier.annotation.isProvenZero)
        #expect(await worker.fileLoadCount == 1)
        _ = await worker.frontier(of: frontier.summary.calls[0].callee)
        #expect(await worker.fileLoadCount == 1, "cached")

        // Marking `area` non-critical: it becomes transparent and total_area proves zero.
        var overrides = CriticalityOverrides()
        overrides.setSymbol(frontier.summary.calls[0].callee.symbol, to: .ordinary)
        await worker.configure(Self.configuration(root: f.root, index: f.index, overrides: overrides, revision: 2))
        let marked = await worker.frontier(in: f.lib, syntax: f.libSyntax, semantics: semantics, owner: total.byteRange,
                                           callable: totalID, hasBody: true)
        #expect(marked.directCritical.isEmpty)
        #expect(marked.paths.isEmpty)
        #expect(marked.traversedBodies == 1)
        #expect(marked.annotation == CountAnnotation(count: 0, completeness: .proven))

        // An external symbol has no body; a non-callable owner with no body is abstract.
        let external = await worker.summary(of: SemanticSymbolID(symbol: "rust-analyzer cargo core . option/Option#unwrap().", document: ""))
        #expect(external.coverage == .noBody(.external))
    }

    @Test func changedCalleeBytesInvalidateSummariesAndDependentFrontiers() async throws {
        let f = try await ContextModelTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let worker = CallGraphWorker()
        await worker.configure(Self.configuration(root: f.root, index: f.index))
        let total = try #require(f.libSyntax.symbols.first { $0.name == "total_area" })
        let semantics = DocumentSemantics.make(document: try #require(f.index.documents["src/lib.rs"]), buffer: f.lib)
        guard case .defines(let totalID) = DeclarationContext.link(for: total, in: semantics) else { Issue.record("total_area not linked"); return }
        var overrides = CriticalityOverrides()
        let areaID = SemanticSymbolID(symbol: "rust-analyzer cargo ra_fixture 0.1.0 shapes/impl#[Circle]area().", document: "")
        overrides.setSymbol(areaID.symbol, to: .ordinary)
        await worker.configure(Self.configuration(root: f.root, index: f.index, overrides: overrides, revision: 2))
        let first = await worker.frontier(in: f.lib, syntax: f.libSyntax, semantics: semantics, owner: total.byteRange, callable: totalID, hasBody: true)
        #expect(first.traversedBodies == 1, "area is traversed as ordinary")
        #expect(first.annotation == CountAnnotation(count: 0, completeness: .proven))
        let summariesBefore = await worker.summaryBuildCount
        let frontiersBefore = await worker.frontierBuildCount
        _ = await worker.frontier(in: f.lib, syntax: f.libSyntax, semantics: semantics, owner: total.byteRange, callable: totalID, hasBody: true)
        #expect(await worker.frontierBuildCount == frontiersBefore, "cached")

        // The callee's file changes with the same length: `area` now calls `new` (critical) once.
        let edited = try SourceBuffer(path: "src/shapes.rs", data: Data(("pub struct Circle {\n    pub radius: f64,\n}\n\nimpl Circle {\n    pub fn new(radius: f64) -> Self { Circle { radius } }\n    pub fn area(&self) -> f64 {\n        let r = self.radius;\n        std::f64::consts::PI * r * r\n    }\n}\n").utf8))
        #expect(edited.data.count == f.shapes.data.count, "same bytes count as the fixture")
        // Prime identical bytes: nothing is dropped.
        await worker.prime(buffer: edited, syntax: f.shapesSyntax, semantics: nil)
        _ = await worker.frontier(in: f.lib, syntax: f.libSyntax, semantics: semantics, owner: total.byteRange, callable: totalID, hasBody: true)
        #expect(await worker.frontierBuildCount == frontiersBefore, "identical bytes keep every cache")
        // Prime same-length different bytes (a comment edit): summaries from
        // the old bytes and every dependent frontier are recomputed.
        var bytes = edited.data
        let marker = try #require(edited.text.range(of: "PI * r * r").map { edited.text.utf8.distance(from: edited.text.startIndex, to: $0.lowerBound) })
        bytes[marker] = UInt8(ascii: "Q")
        let mutated = try SourceBuffer(path: "src/shapes.rs", data: bytes)
        let mutatedSyntax = try #require(try await SyntaxWorker().parse(mutated))
        await worker.prime(buffer: mutated, syntax: mutatedSyntax, semantics: f.index.documents["src/shapes.rs"].map { DocumentSemantics.make(document: $0, buffer: mutated) })
        let rebuilt = await worker.frontier(in: f.lib, syntax: f.libSyntax, semantics: semantics, owner: total.byteRange, callable: totalID, hasBody: true)
        #expect(await worker.frontierBuildCount == frontiersBefore + 1, "the root frontier in lib.rs depended on shapes.rs")
        #expect(await worker.summaryBuildCount >= summariesBefore + 1, "area's summary was rebuilt from the new bytes (the root is re-summarized too)")
        #expect(rebuilt.summary.calls.map(\.displayName) == ["area"])
        let areaSummary = await worker.summary(of: areaID)
        #expect(areaSummary.body?.sourceIdentity == SourceContentIdentity(bytes))
    }

    @Test func reconfigurationDuringALoadNeverPopulatesTheNewCaches() async throws {
        let f = try await ContextModelTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let worker = CallGraphWorker(artificialLoadDelay: .milliseconds(150))
        let areaID = SemanticSymbolID(symbol: "rust-analyzer cargo ra_fixture 0.1.0 shapes/impl#[Circle]area().", document: "")
        await worker.configure(Self.configuration(root: f.root, index: f.index, revision: 1))
        let stale = Task { await worker.frontier(of: areaID) }
        try await Task.sleep(for: .milliseconds(30))
        var overrides = CriticalityOverrides()
        overrides.setSymbol(areaID.symbol, to: .ordinary)
        await worker.configure(Self.configuration(root: f.root, index: f.index, overrides: overrides, revision: 2))
        let staleResult = await stale.value
        #expect(staleResult.coverage == .noBody(.notIndexed), "the operation started under the old epoch yields nothing usable")
        #expect(await worker.fileLoadCount == 0, "and cached no file")
        #expect(await worker.summaryBuildCount == 0, "and no summary")
        let fresh = await worker.frontier(of: areaID)
        #expect(fresh.summary.body?.path == "src/shapes.rs")
        #expect(fresh.annotation.isProvenZero)
        let loads = await worker.fileLoadCount
        let builds = await worker.summaryBuildCount
        #expect(loads == 1 && builds == 1)
    }

    @Test func byteInvalidationDuringAnInFlightLoadNeverResurrectsOldBytes() async throws {
        let f = try await ContextModelTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let worker = CallGraphWorker(artificialLoadDelay: .milliseconds(150))
        let areaID = SemanticSymbolID(symbol: "rust-analyzer cargo ra_fixture 0.1.0 shapes/impl#[Circle]area().", document: "")
        await worker.configure(Self.configuration(root: f.root, index: f.index))
        // Prepare viewer bytes before racing the disk load. Parsing under the
        // parallel suite can exceed the artificial delay; it is not part of
        // the interleaving this regression is intended to exercise.
        var bytes = f.shapes.data
        let marker = try #require(f.shapes.text.range(of: "PI * r * r").map { f.shapes.text.utf8.distance(from: f.shapes.text.startIndex, to: $0.lowerBound) })
        bytes[marker] = UInt8(ascii: "Q")
        let mutated = try SourceBuffer(path: "src/shapes.rs", data: bytes)
        let mutatedSyntax = try #require(try await SyntaxWorker().parse(mutated))
        let stale = Task { await worker.frontier(of: areaID) }
        try await Task.sleep(for: .milliseconds(30))
        await worker.prime(buffer: mutated, syntax: mutatedSyntax, semantics: f.index.documents["src/shapes.rs"].map { DocumentSemantics.make(document: $0, buffer: mutated) })
        let staleResult = await stale.value
        #expect(staleResult.summary.body?.sourceIdentity == SourceContentIdentity(bytes), "the in-flight load yields to the primed bytes")
        #expect(await worker.fileLoadCount == 0, "the disk copy was never cached over the primed bytes")
        let fresh = await worker.summary(of: areaID)
        #expect(fresh.body?.sourceIdentity == SourceContentIdentity(bytes), "the primed bytes win")
        let frontier = await worker.frontier(of: areaID)
        #expect(frontier.summary.body?.sourceIdentity == SourceContentIdentity(bytes))

        // Same bytes, structure arriving later: a no-body answer is not kept.
        let bare = CallGraphWorker()
        await bare.configure(Self.configuration(root: f.root, index: f.index))
        await bare.prime(buffer: f.shapes, syntax: nil, semantics: nil)
        #expect(await bare.summary(of: areaID).coverage == .noBody(.noSyntax))
        #expect(await bare.frontier(of: areaID).coverage == .noBody(.noSyntax))
        await bare.prime(buffer: f.shapes, syntax: f.shapesSyntax, semantics: f.index.documents["src/shapes.rs"].map { DocumentSemantics.make(document: $0, buffer: f.shapes) })
        #expect(await bare.summary(of: areaID).body?.path == "src/shapes.rs", "the upgrade dropped the no-body answer")
        #expect(await bare.frontier(of: areaID).annotation.isProvenZero)
        // A fresh open-file request right after an invalidating prime is still cached.
        let total = try #require(f.libSyntax.symbols.first { $0.name == "total_area" })
        let semantics = DocumentSemantics.make(document: try #require(f.index.documents["src/lib.rs"]), buffer: f.lib)
        guard case .defines(let totalID) = DeclarationContext.link(for: total, in: semantics) else { Issue.record("total_area not linked"); return }
        _ = await bare.frontier(in: f.lib, syntax: f.libSyntax, semantics: semantics, owner: total.byteRange, callable: totalID, hasBody: true)
        let builds = await bare.frontierBuildCount
        _ = await bare.frontier(in: f.lib, syntax: f.libSyntax, semantics: semantics, owner: total.byteRange, callable: totalID, hasBody: true)
        #expect(await bare.frontierBuildCount == builds, "cached after the epoch captured post-prime")
    }

    @Test func unresolvedAndDynamicSitesMakeCoveragePartial() async throws {
        let f = try await ContextModelTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let worker = CallGraphWorker()
        await worker.configure(Self.configuration(root: f.root, index: f.index))
        // A file the index does not describe: every site is unresolved, never silently zero.
        let source = "fn go(f: fn()) { (f)(); helper(); }\nfn helper() {}\n"
        let buffer = try SourceBuffer(path: "src/other.rs", data: Data(source.utf8))
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        let go = try #require(snapshot.symbols.first { $0.name == "go" })
        let summary = await worker.summary(in: buffer, syntax: snapshot, semantics: DocumentSemantics(path: "src/other.rs", occurrences: [], unmappedCount: 0),
                                           owner: go.byteRange, callable: nil, hasBody: true)
        #expect(summary.calls.isEmpty)
        #expect(summary.coverage.gaps?.unresolvedSites == 2)
        let frontier = await CriticalFrontierBuilder().build(root: summary) { _ in nil }
        #expect(frontier.annotation == CountAnnotation(count: 0, completeness: .partial))
        #expect(!frontier.annotation.isProvenZero)
        // Without structure, there is no body to summarize (a fresh worker: the one above keeps the parsed file).
        let bare = CallGraphWorker()
        await bare.configure(Self.configuration(root: f.root, index: f.index))
        let noSyntax = await bare.summary(in: buffer, syntax: nil, semantics: nil, owner: go.byteRange, callable: nil, hasBody: true)
        #expect(noSyntax.coverage == .noBody(.noSyntax))
        // A declaration without a body is abstract.
        let abstract = await worker.summary(in: buffer, syntax: snapshot, semantics: nil, owner: go.byteRange, callable: nil, hasBody: false)
        #expect(abstract.coverage == .noBody(.abstract))
    }
}
