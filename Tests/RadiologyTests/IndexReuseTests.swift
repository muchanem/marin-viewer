import Foundation
import Testing
@testable import Radiology

/// Index reuse across revisions: a strategy is copied only when its content
/// digest proves identical bytes; anything else is regenerated whole.
@Suite(.serialized)
struct IndexReuseTests {
    /// With `extraProject`, the fixture crate lives under `a/` beside a
    /// sibling `other/` crate: two top-level projects, two strategies.
    static func revisionRoot(named name: String, lib: String, shapes: String, extraProject: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-rev-\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        let primary = extraProject ? root.appending(path: "a", directoryHint: .isDirectory) : root
        try FileManager.default.createDirectory(at: primary.appending(path: "src"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: SemanticIndexTests.fixtureRoot.appending(path: "Cargo.toml"), to: primary.appending(path: "Cargo.toml"))
        try Data(lib.utf8).write(to: primary.appending(path: "src/lib.rs"))
        try Data(shapes.utf8).write(to: primary.appending(path: "src/shapes.rs"))
        if extraProject {
            try FileManager.default.createDirectory(at: root.appending(path: "other/src"), withIntermediateDirectories: true)
            try Data("[package]\nname='other'\n".utf8).write(to: root.appending(path: "other/Cargo.toml"))
            try Data("pub fn o() {}\n".utf8).write(to: root.appending(path: "other/src/lib.rs"))
        }
        return root.resolvingSymlinksInPath()
    }

    static func snapshot(_ root: URL, extraProject: Bool) -> RepositorySnapshot {
        let paths = extraProject ? Self.twoProjectPaths : ["Cargo.toml", "src/lib.rs", "src/shapes.rs"]
        let files = paths.map { RepositoryFile(path: $0) }
        return RepositorySnapshot(root: root, files: files, tree: FileNode.tree(files: files), isGit: false)
    }

    static let twoProjectPaths = ["a/Cargo.toml", "a/src/lib.rs", "a/src/shapes.rs", "other/Cargo.toml", "other/src/lib.rs"]

    static func options(root: URL, paths: [String], revision: String, cache: IndexCache, reuse: [IndexReuseSource]) -> IndexOpenOptions {
        IndexOpenOptions(cache: cache, reuseSources: reuse, revision: revision,
                         blobIDs: ContentDigest.workingTreeBlobIDs(root: root, paths: paths))
    }

    @Test func digestsConservativelyCoverSiblingDependencyContext() {
        let strategy = IndexingStrategy(indexerID: "x", projectDirectory: "modules/a", evidence: [], languages: ["Rust"])
        let paths = ["Cargo.toml", "modules/a/src/lib.rs", "modules/b/src/lib.rs", "shared/include.h"]
        #expect(ContentDigest.relevantPaths(for: strategy, in: paths) == paths)
        let ids = Dictionary(uniqueKeysWithValues: paths.map { ($0, ContentDigest.blobID(of: Data($0.utf8))) })
        for path in ["modules/b/src/lib.rs", "shared/include.h", "Cargo.toml"] {
            var changed = ids
            changed[path] = "0000"
            #expect(ContentDigest.digest(for: strategy, blobIDs: ids) != ContentDigest.digest(for: strategy, blobIDs: changed))
        }
        #expect(ContentDigest.blobID(of: Data("hello\n".utf8)) == "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    @Test func identicalBytesReuseAnotherRevisionsIndexWithoutRunningTheTool() async throws {
        let lib = try String(contentsOf: SemanticIndexTests.fixtureRoot.appending(path: "src/lib.rs"), encoding: .utf8)
        let shapes = try String(contentsOf: SemanticIndexTests.fixtureRoot.appending(path: "src/shapes.rs"), encoding: .utf8)
        let first = try Self.revisionRoot(named: "a", lib: lib, shapes: shapes, extraProject: false)
        let second = try Self.revisionRoot(named: "b", lib: lib, shapes: shapes, extraProject: false)
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-reuse-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second); try? FileManager.default.removeItem(at: cacheRoot) }
        let paths = ["Cargo.toml", "src/lib.rs", "src/shapes.rs"]
        let cacheA = IndexCache(root: cacheRoot.appending(path: "revisions/aaa/index"), flat: true)
        let cacheB = IndexCache(root: cacheRoot.appending(path: "revisions/bbb/index"), flat: true)
        let working = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(IndexingTests.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let tools = ToolDirectory(url: cacheRoot.appending(path: "tools"))

        let generate = SemanticIndexService(indexers: [working], cache: .default, tools: tools)
        let sinkA = PublicationSink()
        await generate.open(Self.snapshot(first, extraProject: false), options: Self.options(root: first, paths: paths, revision: "aaa", cache: cacheA, reuse: [])) { await sinkA.receive($0) }
        try await IndexingTests.waitUntil { sinkA.latest?.status == .current }
        #expect(await sinkA.latest?.outcomes.first?.result == .generated)
        let metadataA = try #require(cacheA.loadMetadata(for: first))
        #expect(metadataA.revision == "aaa")
        #expect(metadataA.formatVersion == 3)
        let digest = try #require(metadataA.strategies.first?.contentDigest)
        #expect(FileManager.default.fileExists(atPath: cacheA.root.appending(path: "fake.scip").path))

        // Revision bbb has identical bytes: the tool must not run (it would fail).
        let failing = FakeIndexer(id: "fake", displayName: "Fake", script: "exit 9", marker: "Cargo.toml", installable: true)
        let reuse = SemanticIndexService(indexers: [failing], cache: .default, tools: tools)
        let sinkB = PublicationSink()
        let sources = [IndexReuseSource(cache: cacheA, root: first, label: "aaa")]
        await reuse.open(Self.snapshot(second, extraProject: false), options: Self.options(root: second, paths: paths, revision: "bbb", cache: cacheB, reuse: sources)) { await sinkB.receive($0) }
        try await IndexingTests.waitUntil { sinkB.latest?.status == .current }
        #expect(await sinkB.latest?.outcomes.first?.result == .reused(from: "aaa"))
        #expect(await sinkB.latest?.index.documentCount == 2)
        let metadataB = try #require(cacheB.loadMetadata(for: second))
        #expect(metadataB.strategies.first?.contentDigest == digest)
        #expect(metadataB.strategies.first?.reusedFrom == "aaa")
        #expect(FileManager.default.fileExists(atPath: cacheB.root.appending(path: "fake.scip").path), "the copy lives in bbb's own cache")

        // Reopening bbb is Current from its own cache, by digest, without any source.
        let again = SemanticIndexService(indexers: [failing], cache: .default, tools: tools)
        let sinkC = PublicationSink()
        await again.open(Self.snapshot(second, extraProject: false), options: Self.options(root: second, paths: paths, revision: "bbb", cache: cacheB, reuse: [])) { await sinkC.receive($0) }
        try await IndexingTests.waitUntil { sinkC.latest?.status == .current }
        #expect(await sinkC.latest?.outcomes.first?.result == .cached(stale: false))

        // A format-2 record (no digest) at the same path is never reused, even with identical bytes.
        var legacy = metadataA
        legacy.strategies = legacy.strategies.map { record in
            var record = record
            record.contentDigest = nil
            return record
        }
        legacy.formatVersion = 2
        let cacheL = IndexCache(root: cacheRoot.appending(path: "legacy"), flat: true)
        try FileManager.default.createDirectory(at: cacheL.root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: cacheA.root.appending(path: "fake.scip"), to: cacheL.root.appending(path: "fake.scip"))
        try cacheL.save(legacy, for: first)
        let cacheD = IndexCache(root: cacheRoot.appending(path: "revisions/ddd/index"), flat: true)
        let noReuse = SemanticIndexService(indexers: [failing], cache: .default, tools: tools)
        let sinkD = PublicationSink()
        await noReuse.open(Self.snapshot(second, extraProject: false), options: Self.options(root: second, paths: paths, revision: "ddd", cache: cacheD, reuse: [IndexReuseSource(cache: cacheL, root: first, label: "legacy")])) { await sinkD.receive($0) }
        try await IndexingTests.waitUntil { if case .failed = sinkD.latest?.status { true } else { false } }
        guard case .failed(let failure)? = await sinkD.latest?.outcomes.first?.result else { Issue.record("expected regeneration to be attempted"); return }
        #expect(failure.exitStatus == 9)
    }

    @Test func changedDependencyContextRegeneratesAndPersistedMixedProvenanceStaysPartial() async throws {
        let lib = try String(contentsOf: SemanticIndexTests.fixtureRoot.appending(path: "src/lib.rs"), encoding: .utf8)
        let shapes = try String(contentsOf: SemanticIndexTests.fixtureRoot.appending(path: "src/shapes.rs"), encoding: .utf8)
        let base = try Self.revisionRoot(named: "base", lib: lib, shapes: shapes, extraProject: true)
        let head = try Self.revisionRoot(named: "head", lib: lib, shapes: shapes + "\n// changed\n", extraProject: true)
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-reuse-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base); try? FileManager.default.removeItem(at: head); try? FileManager.default.removeItem(at: cacheRoot) }
        let paths = Self.twoProjectPaths
        let cacheBase = IndexCache(root: cacheRoot.appending(path: "revisions/base/index"), flat: true)
        let cacheHead = IndexCache(root: cacheRoot.appending(path: "revisions/head/index"), flat: true)
        let tools = ToolDirectory(url: cacheRoot.appending(path: "tools"))
        let working = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(IndexingTests.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let generate = SemanticIndexService(indexers: [working], cache: .default, tools: tools)
        let sinkBase = PublicationSink()
        await generate.open(Self.snapshot(base, extraProject: true), options: Self.options(root: base, paths: paths, revision: "base", cache: cacheBase, reuse: [])) { await sinkBase.receive($0) }
        try await IndexingTests.waitUntil { sinkBase.latest?.status == .current }
        #expect(await sinkBase.latest?.outcomes.count == 2)

        // Sibling dependencies are not modeled: changing a/src/shapes.rs invalidates both projects.
        let marker = cacheRoot.appending(path: "ran-\(UUID().uuidString)")
        let counting = FakeIndexer(id: "fake", displayName: "Fake", script: "echo ran >> '\(marker.path)'; cp '\(IndexingTests.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [counting], cache: .default, tools: tools)
        let sink = PublicationSink()
        await service.open(Self.snapshot(head, extraProject: true), options: Self.options(root: head, paths: paths, revision: "head", cache: cacheHead, reuse: [IndexReuseSource(cache: cacheBase, root: base, label: "base")])) { await sink.receive($0) }
        try await IndexingTests.waitUntil { sink.latest?.status == .current }
        let outcomes = try #require(await sink.latest?.outcomes)
        let byID = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.id, $0.result) })
        #expect(byID["fake@a"] == .generated)
        #expect(byID["fake@other"] == .generated)
        let runs = (try? String(contentsOf: marker, encoding: .utf8))?.split(separator: "\n").count ?? 0
        #expect(runs == 2, "unknown sibling dependencies conservatively regenerate both strategies")
        // Recover provenance from an existing mixed cache, regardless of this
        // run's .cached outcomes. Also exercise the loaded-cache refresh branch.
        var mixed = try #require(cacheHead.loadMetadata(for: head))
        mixed.strategies[1].reusedFrom = "base"
        try cacheHead.save(mixed, for: head)
        let failing = FakeIndexer(id: "fake", displayName: "Fake", script: "exit 9", marker: "Cargo.toml", installable: true)
        let reload = SemanticIndexService(indexers: [failing], cache: .default, tools: tools)
        let reloaded = PublicationSink()
        let options = Self.options(root: head, paths: paths, revision: "head", cache: cacheHead, reuse: [])
        await reload.open(Self.snapshot(head, extraProject: true), options: options) { await reloaded.receive($0) }
        try await IndexingTests.waitUntil { if case .partial = reloaded.latest?.status { true } else { false } }
        #expect(await reloaded.latest?.outcomes.allSatisfy { $0.result == .cached(stale: false) } == true)
        guard case .partial(let reason)? = await reloaded.latest?.status else { return }
        #expect(reason.contains("reused") && reason.contains("regenerated"))
        let refreshed = PublicationSink()
        await reload.refresh(Self.snapshot(head, extraProject: true)) { await refreshed.receive($0) }
        try await IndexingTests.waitUntil { if case .partial = refreshed.latest?.status { true } else { false } }

        #expect(await sink.latest?.index.documentCount == 4)
    }
}
