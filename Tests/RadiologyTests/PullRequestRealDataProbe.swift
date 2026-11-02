import Foundation
import Testing
@testable import Radiology

/// Opt-in, read-only exercise of the real pull request pipeline against the
/// tkos checkout and GitHub: `RADIOLOGY_REAL_PR_PROBE=1 swift test --filter
/// PullRequestRealDataProbe`. It needs `gh` logged in and network access. It
/// uses a temporary cache directory (removed afterwards) so the reader's own
/// cache and the tkos repository are untouched; it never writes to GitHub.
struct PullRequestRealDataProbe {
    static let tkos = URL(filePath: "/Users/tqbf/codebase/tk/tkos", directoryHint: .isDirectory)

    @Test func readsRecentPullRequestsAndDiffsThreeRealCases() async throws {
        guard ProcessInfo.processInfo.environment["RADIOLOGY_REAL_PR_PROBE"] == "1",
              FileManager.default.fileExists(atPath: Self.tkos.path), GHCommandClient.executable() != nil else {
            print("real pull request probe skipped (set RADIOLOGY_REAL_PR_PROBE=1 with tkos and gh available)")
            return
        }
        let status = try GitFixture.run(["status", "--porcelain", "--branch"], in: Self.tkos)
        let head = try GitFixture.run(["rev-parse", "HEAD"], in: Self.tkos)
        let cache = FileManager.default.temporaryDirectory.appending(path: "radiology-pr-probe-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: cache) }
        let client = GHCommandClient()
        let repository = try await client.repository(at: Self.tkos)
        print("probe: repository \(repository.nameWithOwner) default \(repository.defaultBranch)")
        let recent = try await client.listPullRequests(in: repository, limit: PullRequestModel.recentLimit)
        print("probe: \(recent.count) recent pull requests, newest #\(recent.first?.number ?? 0), states \(Dictionary(grouping: recent, by: \.state).mapValues(\.count))")
        #expect(recent.count == PullRequestModel.recentLimit)
        let store = try ReviewRepository(attachedRoot: Self.tkos, cacheDirectory: cache)
        for number in [724, 723, 725] {
            let summary = try await client.pullRequest(number: number, in: repository)
            let base = try await client.mergeBase(base: summary.baseRefOid, head: summary.headRefOid, in: repository)
            let started = ContinuousClock.now
            try await store.fetch([summary.headRefOid, base], fallbackRefs: ["refs/pull/\(number)/head"])
            let fetched = started.duration(to: .now)
            let changes = try await store.changes(base: base, head: summary.headRefOid)
            let counts = Dictionary(grouping: changes, by: { change -> String in
                switch change.status {
                case .added: "A"
                case .modified: "M"
                case .deleted: "D"
                case .renamed: "R"
                case .copied: "C"
                case .other(let letter): letter
                }
            }).mapValues(\.count)
            print("probe: #\(number) \(summary.state) head \(summary.headRefOid.prefix(10)) merge-base \(base.prefix(10)) fetch \(fetched) files \(changes.count) \(counts) binary \(changes.count { $0.isBinary })")
            #expect(!changes.isEmpty)
            if number == 724 {
                #expect(base == "488d8768d55a4e88a772c673bada7d89168aed0f")
                let byPath = Dictionary(uniqueKeysWithValues: changes.map { ($0.path, $0) })
                let smoke = try #require(byPath["tools/tk-desktop/src/main/kotlin/inc/tk/os/engine/RuntimeSmoke.kt"])
                #expect(smoke.additions == 117 && smoke.deletions == 205)
                let session = try #require(byPath["tools/tk-desktop/src/main/kotlin/inc/tk/os/engine/DesktopRuntimeSession.kt"])
                #expect(session.additions == 0 && session.deletions == 55, "a deletion-only modification")
                let process = try #require(byPath["tools/tk-desktop/src/main/kotlin/inc/tk/os/engine/DesktopRuntimeProcess.kt"])
                #expect(process.status == .added && process.additions == 206)
                let sessionHunks = try await store.lineChanges(base: base, head: summary.headRefOid, change: session)
                print("probe: #724 DesktopRuntimeSession.kt removed lines \(sessionHunks.changedLines(in: .before)) added \(sessionHunks.changedLines(in: .after)) anchors(after) \(sessionHunks.changeAnchors(in: .after))")
                #expect(sessionHunks.changedLines(in: .after).isEmpty && sessionHunks.deletions == 55)
                let smokeHunks = try await store.lineChanges(base: base, head: summary.headRefOid, change: smoke)
                print("probe: #724 RuntimeSmoke.kt hunks \(smokeHunks.hunks.count) +\(smokeHunks.additions) -\(smokeHunks.deletions)")
                #expect(smokeHunks.additions == 117 && smokeHunks.deletions == 205)
                let root = try await store.materialize(blob: session.beforeBlob, path: session.path, revision: base)
                let before = try SourceBuffer(path: session.path, data: Data(contentsOf: root.appending(path: session.path)))
                print("probe: #724 Before DesktopRuntimeSession.kt \(before.lineCount) lines")
                let worktree = try await store.worktree(for: summary.headRefOid)
                let after = try SourceBuffer(path: session.path, data: Data(contentsOf: worktree.appending(path: session.path)))
                print("probe: #724 After DesktopRuntimeSession.kt \(after.lineCount) lines; worktree \(worktree.path)")
                #expect(before.lineCount - after.lineCount == 55)
                let tree = try await store.tree(of: summary.headRefOid)
                print("probe: #724 head tree \(tree.count) entries")
                let inspection = RepositoryInspection(root: worktree, paths: tree.map(\.path), isGit: true)
                let strategies = SemanticIndexerRegistry.strategies(for: inspection).selected
                let ids = Dictionary(uniqueKeysWithValues: tree.map { ($0.path, $0.blob) })
                let baseTree = try await store.tree(of: base)
                let baseIDs = Dictionary(uniqueKeysWithValues: baseTree.map { ($0.path, $0.blob) })
                let unchanged = strategies.filter { ContentDigest.digest(for: $0, blobIDs: ids) == ContentDigest.digest(for: $0, blobIDs: baseIDs) }
                print("probe: #724 \(strategies.count) strategies at head; \(unchanged.count) have identical bytes to the merge base and would reuse a base index")
            }
            if number == 725 {
                let renames = changes.filter { if case .renamed = $0.status { true } else { false } }
                print("probe: #725 renames \(renames.map { "\($0.oldPath ?? "") -> \($0.path) \($0.status.title)" }.prefix(4))")
                #expect(!renames.isEmpty)
            }
            if number == 723 {
                #expect(summary.isMerged)
            }
        }
        #expect(try GitFixture.run(["status", "--porcelain", "--branch"], in: Self.tkos) == status, "tkos status is unchanged")
        #expect(try GitFixture.run(["rev-parse", "HEAD"], in: Self.tkos) == head)
    }
    /// Bounded actual adapter/index/cache smoke; selects one small real project.
    @Test func actualAfterSnapshotRustIndexReuseAndDependencyInvalidation() async throws {
        guard ProcessInfo.processInfo.environment["RADIOLOGY_REAL_PR_INDEX_PROBE"] == "1" else { return }
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-pr-index-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let client = GHCommandClient()
        let repo = try await client.repository(at: Self.tkos)
        let summary = try await client.pullRequest(number: 724, in: repo)
        let store = try ReviewRepository(attachedRoot: Self.tkos, cacheDirectory: cacheRoot.appending(path: "review"))
        try await store.fetch([summary.headRefOid])
        let root = try await store.worktree(for: summary.headRefOid)
        let tree = try await store.tree(of: summary.headRefOid)
        let ids = Dictionary(uniqueKeysWithValues: tree.map { ($0.path, $0.blob) })
        let project = "tools/phone-provisioner"
        let files = tree.filter { $0.path.hasPrefix(project + "/") }.map { RepositoryFile(path: $0.path) }
        #expect(files.contains { $0.path == project + "/Cargo.toml" })
        let snapshot = RepositorySnapshot(root: root, files: files, tree: FileNode.tree(files: files), isGit: true)
        let tools = ToolDirectory(url: cacheRoot.appending(path: "tools"))
        let adapter = RustAnalyzerIndexer()
        guard case .available(_, let version) = await ToolProvisioner(tools: tools).availability(of: adapter) else {
            Issue.record("Installed rust-analyzer unavailable for actual snapshot smoke")
            return
        }
        let cacheA = IndexCache(root: cacheRoot.appending(path: "index-a"), flat: true)
        let cacheB = IndexCache(root: cacheRoot.appending(path: "index-b"), flat: true)
        let cacheC = IndexCache(root: cacheRoot.appending(path: "index-c"), flat: true)
        func run(cache: IndexCache, blobIDs: [String: String], reuse: [IndexReuseSource]) async throws -> SemanticPublication {
            let service = SemanticIndexService(indexers: [adapter], cache: cache, tools: tools)
            let sink = PublicationSink()
            let started = ContinuousClock.now
            await service.open(snapshot, options: IndexOpenOptions(cache: cache, reuseSources: reuse,
                               revision: summary.headRefOid, blobIDs: blobIDs)) { await sink.receive($0) }
            try await IndexingTests.waitUntil(.seconds(110)) {
                guard let status = sink.latest?.status else { return false }
                switch status { case .indexing: return false; default: return true }
            }
            let publication = try #require(await sink.latest)
            await service.cancel()
            print("index probe: \(summary.headRefOid) \(project) \(version) \(started.duration(to: .now)) status \(publication.status) outcomes \(publication.outcomes.map(\.result)) docs \(publication.index.documentCount)")
            #expect(publication.outcomes.count == 1)
            return publication
        }
        let generated = try await run(cache: cacheA, blobIDs: ids, reuse: [])
        #expect(generated.outcomes.first?.result == .generated)
        #expect(generated.index.documentCount > 0)
        var mapped = 0
        for (path, document) in generated.index.documents {
            let buffer = try SourceBuffer(path: path, data: Data(contentsOf: root.appending(path: path)))
            let semantics = DocumentSemantics.make(document: document, buffer: buffer)
            #expect(semantics.unmappedCount == 0)
            mapped += semantics.occurrences.count
        }
        #expect(mapped > 0)
        print("index probe: validated \(mapped) occurrences against exact After bytes")
        let reused = try await run(cache: cacheB, blobIDs: ids, reuse: [IndexReuseSource(cache: cacheA, root: root, label: "actual-head")])
        #expect(reused.outcomes.first?.result == .reused(from: "actual-head"))
        var changed = ids
        // Simulate changed sibling provenance without editing any snapshot bytes.
        changed["modules/agent/ffi/src/app.rs"] = ContentDigest.blobID(of: Data("changed dependency context".utf8))
        let regenerated = try await run(cache: cacheC, blobIDs: changed, reuse: [IndexReuseSource(cache: cacheA, root: root, label: "actual-head")])
        #expect(regenerated.outcomes.first?.result == .generated)
    }

}
