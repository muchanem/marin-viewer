import Foundation
import Testing
@testable import Radiology

@Suite(.serialized)
@MainActor
struct PRRefreshTests {
    func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !predicate(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(predicate(), "refresh test timed out")
    }
    func summary(_ fixture: GitFixture, head: String? = nil, base: String? = nil, number: Int = 1, title: String = "Updated") -> PullRequestSummary {
        PullRequestSummary(number: number, title: title, state: "OPEN", baseRefName: "main", baseRefOid: base ?? fixture.mainSHA,
                           headRefName: "feature", headRefOid: head ?? fixture.headSHA, isCrossRepository: false,
                           updatedAt: .now, mergeCommit: nil, author: nil)
    }
    func boot(_ fixture: GitFixture, initial: PullRequestSummary? = nil) async throws -> (AppModel, FakeGitHubClient) {
        let value = initial ?? summary(fixture)
        let client = FakeGitHubClient(summaries: [1: value], mergeBase: fixture.baseSHA)
        let cache = IndexCache(root: fixture.directory.appending(path: "refresh-cache"))
        let semantic = SemanticModel(service: SemanticIndexService(indexers: [], cache: cache,
            tools: ToolDirectory(url: fixture.directory.appending(path: "tools"))))
        let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
        let model = AppModel(preferences: preferences, semantics: semantic,
                             pullRequests: PullRequestModel(client: client, workingTreeCache: cache, worktreeLimit: 1))
        model.openRepository(fixture.attached)
        try await wait { !model.isOpening }
        model.openPullRequest(1)
        try await wait { model.review != nil && !model.isOpening && model.repository != nil }
        model.openFile("src/lib.rs")
        try await wait { model.syntax?.path == "src/lib.rs" && model.reviewHighlights != nil && !model.semantics.status.isIndexing }
        return (model, client)
    }
    func prefixedHead(_ fixture: GitFixture) async throws -> String {
        try await Task.detached {
            try GitFixture.run(["checkout", "-q", "feature"], in: fixture.origin)
            let file = fixture.origin.appending(path: "src/lib.rs")
            let old = try String(contentsOf: file, encoding: .utf8)
            try GitFixture.write("// update\n" + old, to: file)
            try GitFixture.run(["commit", "-q", "-am", "updated PR"], in: fixture.origin)
            return try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin)
        }.value
    }
    func setUpdate(_ fixture: GitFixture, _ client: FakeGitHubClient, head: String, base: String? = nil) {
        let value = summary(fixture, head: head, base: base)
        client.summaries[1] = value
        client.mergeBases["\(value.baseRefOid)...\(value.headRefOid)"] = base ?? fixture.baseSHA
    }

    @Test func sameHeadAndBaseIsMetadataOnlyAndCommandRouteCoalesces() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let (model, client) = try await boot(fixture)
        let source = try #require(model.source)
        model.caretMoved(to: source.byteOffset(line: 10) + 1)
        let group = OccurrenceGroup(identity: .syntactic(scope: 0..<source.data.count, spelling: Data("c".utf8)),
                                    activeByteRange: 0..<1, byteRanges: [0..<1])
        model.occurrencePins.toggle(group, path: source.positionKey, sourceIdentity: SourceContentIdentity(source.data), clickedByte: 0)
        let pins = model.occurrencePins
        let syntax = model.syntax
        let history = model.history.current
        let navigation = model.navigationRevision
        let caret = model.currentCaretLocation
        let index = model.semantics.indexRevision
        let calls = client.viewCalls
        client.summaries[1] = summary(fixture, title: "Fresh title")
        client.pullRequestDelay = .milliseconds(100)
        model.refresh(); model.refresh() // same keyboard route; no duplicate fetch
        #expect(model.pullRequests.isRefreshing && !model.canRefreshPR)
        try await wait { !model.pullRequests.isLoading }
        #expect(client.viewCalls == calls + 1)
        #expect(model.review?.title == "Fresh title" && model.pullRequests.recent.first?.title == "Fresh title")
        #expect(model.source?.data == source.data && model.syntax == syntax && model.history.current == history)
        #expect(model.navigationRevision == navigation && model.currentCaretLocation == caret && model.occurrencePins == pins)
        #expect(model.semantics.indexRevision == index)
        model.exitPullRequest()
        try await wait { !model.isOpening && model.repository != nil }
        model.refresh() // outside PR this remains a local repository reload
        try await wait { !model.isOpening && model.repository != nil }
        #expect(model.review == nil && model.repository?.root == fixture.attached)
    }

    @Test func changedHeadRestoresLatestCaretAndViewportAndPreservesOptions() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let attached = try GitFixture.run(["status", "--porcelain", "--branch"], in: fixture.attached)
        let (model, client) = try await boot(fixture)
        let old = try #require(model.source)
        let head = try await prefixedHead(fixture)
        setUpdate(fixture, client, head: head)
        client.pullRequestDelay = .milliseconds(150)
        model.sourceMode = .critical; model.sourceFontSize = 17
        model.sourceFilters = .init(hidesTests: true, sourceFilesOnly: true)
        model.mode = .files; model.fileTreeExpansion.setExpanded(true, path: "src")
        model.caretMoved(to: old.byteOffset(line: 2))
        model.refreshCurrentPR()
        #expect(model.review?.headSHA == fixture.headSHA && model.source?.data == old.data)
        // Continue reading after clicking refresh: commit must use THIS position.
        model.caretMoved(to: old.byteOffset(line: 8) + 4)
        model.updatePosition(path: old.path, byteOffset: old.byteOffset(line: 11), line: 8)
        try await wait { !model.pullRequests.isLoading && model.review?.headSHA == head }
        let fresh = try #require(model.source)
        #expect(fresh.text.hasPrefix("// update") && fresh.revision == .after)
        #expect(model.currentCaretLocation == fresh.location(atByte: fresh.byteOffset(line: 9) + 4))
        #expect(model.refreshedViewport?.byteOffset == fresh.byteOffset(line: 12))
        #expect(!model.history.canGoBack)
        #expect(model.sourceMode == .critical && model.sourceFontSize == 17 && model.sourceFilters.isActive)
        #expect(model.mode == .files && model.fileTreeExpansion.isExpanded("src"))
        try await wait { model.reviewHighlights?.sourceIdentity == SourceContentIdentity(fresh.data) }
        #expect(model.review?.changes.first(where: { $0.path == old.path })?.additions != nil)
        #expect(try GitFixture.run(["status", "--porcelain", "--branch"], in: fixture.attached) == attached)
        model.pullRequests.cancelOpen()
    }

    @Test func sameHeadNewBaseRefreshesBeforeBytesAndDiffs() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let head = try await prefixedHead(fixture)
        let (model, client) = try await boot(fixture, initial: summary(fixture, head: head))
        model.setRevision(.before)
        try await wait { model.source?.revision == .before && !model.isLoadingSource }
        #expect(model.source?.text.contains("pub fn c()") == false)
        setUpdate(fixture, client, head: head, base: fixture.headSHA)
        model.refreshCurrentPR()
        try await wait { !model.pullRequests.isLoading && model.review?.baseSHA == fixture.headSHA }
        #expect(model.source?.revision == .before && model.source?.text.contains("pub fn c()") == true)
        #expect(model.review?.headSHA == head && model.review?.changes.count == 1)
        #expect(model.semantics.documentSemantics == nil && model.semanticAvailability == .revisionNotIndexed)
        #expect(model.pullRequests.revisionChoices["src/lib.rs"] == .before && !model.history.canGoBack)
        model.setRevision(.after)
        try await wait { model.source?.revision == .after && !model.isLoadingSource }
        let deleted = try await Task.detached {
            try GitFixture.run(["rm", "src/lib.rs"], in: fixture.origin)
            try GitFixture.run(["commit", "-q", "-m", "delete reviewed file"], in: fixture.origin)
            return try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin)
        }.value
        setUpdate(fixture, client, head: deleted, base: fixture.headSHA)
        model.refreshCurrentPR()
        try await wait { !model.pullRequests.isLoading && model.review?.headSHA == deleted }
        #expect(model.source?.revision == .before && model.revisionControl?.available == [.before])
        #expect(model.pullRequests.refreshNotice?.contains("Before") == true)
    }

    @Test func failuresRetryIntentAndProtectedWorktreeSurvivesPreparationFailure() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let (model, client) = try await boot(fixture)
        let old = try #require(model.source)
        let oldRoot = try #require(model.review?.headRoot)
        let navigation = model.navigationRevision
        let head = try await prefixedHead(fixture)
        setUpdate(fixture, client, head: head)
        client.pullRequestError = "offline"
        model.refreshCurrentPR()
        try await wait { model.pullRequests.loadError != nil }
        #expect(model.pullRequests.failedRefresh && model.source?.data == old.data && model.navigationRevision == navigation)
        client.pullRequestError = nil
        model.pullRequests.prepareRefresh = { _, _, _, _ in throw BrowserError.message("source preparation failed") }
        model.pullRequests.retryFailedReview()
        #expect(model.pullRequests.isRefreshing)
        try await wait { model.pullRequests.loadError?.contains("preparation") == true }
        #expect(model.review?.headSHA == fixture.headSHA && model.source?.data == old.data)
        #expect(FileManager.default.fileExists(atPath: oldRoot.appending(path: old.path).path), "limit=1 cannot evict active old reader")
        var preparingCandidate = false
        model.pullRequests.prepareRefresh = { _, _, _, _ in
            preparingCandidate = true
            try await Task.sleep(for: .seconds(4))
            throw BrowserError.message("should be cancelled")
        }
        model.pullRequests.retryFailedReview()
        try await wait { preparingCandidate }
        model.pullRequests.cancelOpen()
        try await Task.sleep(for: .milliseconds(200))
        #expect(model.review?.headSHA == fixture.headSHA && model.source?.data == old.data && model.pullRequests.loadError == nil)
        #expect(FileManager.default.fileExists(atPath: oldRoot.appending(path: old.path).path), "cancelled candidate cannot evict active old root")
        model.pullRequests.prepareRefresh = { [weak model] old, new, snapshot, store in
            guard let model else { throw CancellationError() }
            return try await model.preparePRRefresh(old: old, new: new, snapshot: snapshot, store: store)
        }
        model.refreshCurrentPR()
        try await wait { !model.pullRequests.isLoading && model.review?.headSHA == head }
        #expect(model.source?.text.hasPrefix("// update") == true)
    }

    @Test func pendingRevisionLoadAtPreparationRestoresLatestRequestedReader() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let (model, client) = try await boot(fixture)
        let head = try await prefixedHead(fixture)
        setUpdate(fixture, client, head: head)
        var sawPending = false
        model.pullRequests.prepareRefresh = { [weak model] old, new, snapshot, store in
            guard let model else { throw CancellationError() }
            model.setRevision(.before)
            sawPending = model.source == nil && model.isLoadingSource
            return try await model.preparePRRefresh(old: old, new: new, snapshot: snapshot, store: store)
        }
        model.refreshCurrentPR()
        try await wait { !model.pullRequests.isLoading && model.review?.headSHA == head }
        #expect(sawPending && model.source?.path == "src/lib.rs" && model.source?.revision == .before)
        #expect(model.semanticAvailability == .revisionNotIndexed)
    }

    @Test func renamePreservesExactBytePinsAndMissingFileFallsBackHonestly() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let (model, client) = try await boot(fixture)
        let original = try #require(model.source)
        model.caretMoved(to: original.byteOffset(line: 10) + 2)
        let group = OccurrenceGroup(identity: .syntactic(scope: 0..<original.data.count, spelling: Data("c".utf8)),
                                    activeByteRange: 0..<1, byteRanges: [0..<1])
        model.occurrencePins.toggle(group, path: original.positionKey, sourceIdentity: SourceContentIdentity(original.data), clickedByte: 0)
        let head = try await Task.detached {
            try GitFixture.run(["checkout", "-q", "feature"], in: fixture.origin)
            try GitFixture.run(["mv", "src/lib.rs", "src/moved.rs"], in: fixture.origin)
            try GitFixture.run(["commit", "-q", "-m", "rename"], in: fixture.origin)
            return try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin)
        }.value
        setUpdate(fixture, client, head: head)
        model.refreshCurrentPR()
        try await wait { !model.pullRequests.isLoading && model.review?.headSHA == head }
        let renamed = try #require(model.source)
        #expect(renamed.path == "src/moved.rs" && renamed.data == original.data)
        #expect(model.currentCaretLocation?.byteOffset == original.byteOffset(line: 10) + 2)
        #expect(model.occurrencePins.groups(path: renamed.positionKey, sourceIdentity: SourceContentIdentity(renamed.data)).count == 1)
        // An old added file removed from the new head has neither side in the new PR.
        model.openFile("src/new.rs")
        try await wait { model.source?.path == "src/new.rs" && !model.isLoadingSource }
        let removed = try await Task.detached {
            try GitFixture.run(["rm", "src/new.rs"], in: fixture.origin)
            try GitFixture.run(["commit", "-q", "-m", "remove former addition"], in: fixture.origin)
            return try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin)
        }.value
        setUpdate(fixture, client, head: removed)
        model.refreshCurrentPR()
        try await wait { !model.pullRequests.isLoading && model.review?.headSHA == removed }
        #expect(model.source == nil && model.mode == .changes && model.pullRequests.refreshNotice?.contains("absent") == true)
        #expect(model.navigationTarget == nil && !model.history.canGoBack)
    }

    @Test func cancelDifferentPRAndRepositorySwitchDiscardRefreshCompletion() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let (model, client) = try await boot(fixture)
        let oldRoot = try #require(model.review?.headRoot)
        let head = try await prefixedHead(fixture)
        setUpdate(fixture, client, head: head)
        client.pullRequestDelay = .milliseconds(200); client.ignoresPullRequestCancellation = true
        model.refreshCurrentPR(); model.pullRequests.cancelOpen()
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.review?.headSHA == fixture.headSHA && model.pullRequests.loadError == nil)
        #expect(FileManager.default.fileExists(atPath: oldRoot.path))
        client.summaries[2] = summary(fixture, number: 2)
        client.mergeBases["\(fixture.mainSHA)...\(fixture.headSHA)"] = fixture.baseSHA
        model.refreshCurrentPR(); model.openPullRequest(2)
        try await wait { (model.review?.number == 2 && !model.isOpening) || model.pullRequests.loadError != nil }
        #expect(model.pullRequests.loadError == nil)
        #expect(model.review?.headSHA == fixture.headSHA)
        model.refreshCurrentPR(); model.exitPullRequest()
        try await wait { model.review == nil && !model.isOpening }
        #expect(model.repository?.root == fixture.attached)
        model.openPullRequest(1)
        try await wait { (model.review?.number == 1 && !model.isOpening) || model.pullRequests.loadError != nil }
        #expect(model.pullRequests.loadError == nil)
        model.refreshCurrentPR()
        let other = fixture.directory.appending(path: "other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try GitFixture.write("other", to: other.appending(path: "a.txt"))
        model.openRepository(other)
        try await wait { !model.isOpening }
        #expect(model.repository?.root.resolvingSymlinksInPath().path == other.resolvingSymlinksInPath().path)
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.review == nil && model.pullRequests.loadError == nil)
    }
}
