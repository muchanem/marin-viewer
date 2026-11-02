import Foundation
import Testing
import Observation
@testable import Radiology

@Suite(.serialized)
@MainActor
struct PullRequestReviewTests {
    private static func waitUntil(_ timeout: Duration = .seconds(30), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition(), "timed out")
    }

    private static func model(_ fixture: GitFixture, client: FakeGitHubClient, worktreeLimit: Int = ReviewRepository.worktreeLimit) throws -> (AppModel, IndexCache) {
        let cache = IndexCache(root: fixture.directory.appending(path: "index-cache", directoryHint: .isDirectory))
        let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
        let semantics = SemanticModel(service: SemanticIndexService(indexers: [], cache: cache, tools: ToolDirectory(url: fixture.directory.appending(path: "tools"))))
        let pullRequests = PullRequestModel(client: client, workingTreeCache: cache, worktreeLimit: worktreeLimit)
        return (AppModel(preferences: preferences, semantics: semantics, pullRequests: pullRequests), cache)
    }

    @Test func decodesGhSummariesAndTimesOutSlowCommands() async throws {
        let json = """
        [{"baseRefName":"main","baseRefOid":"488d8768d55a4e88a772c673bada7d89168aed0f","headRefName":"codex/x","headRefOid":"c9a5b0502e8cad8f06440466c8f2124422ee6a23","isCrossRepository":false,"mergeCommit":null,"number":724,"state":"OPEN","title":"Own desktop runtime","updatedAt":"2026-10-04T22:11:41Z","author":{"id":"x","is_bot":false,"login":"dadrian","name":"D"}},
         {"baseRefName":"main","baseRefOid":"8368298660b3a5a15398a88767775a610779b90f","headRefName":"b","headRefOid":"f4082f9e3ab0f5b363ff5300acd7bf8ccf78a19e","isCrossRepository":true,"mergeCommit":{"oid":"6af21769e85adea14949be3105af4a65c43ad8b2"},"number":723,"state":"MERGED","title":"Build","updatedAt":"2026-10-04T21:32:49Z","author":null}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let summaries = try decoder.decode([PullRequestSummary].self, from: Data(json.utf8))
        #expect(summaries.map(\.number) == [724, 723])
        #expect(summaries[0].author?.login == "dadrian" && summaries[0].mergeCommit == nil && summaries[0].stateTitle == "Open")
        #expect(summaries[1].isMerged && summaries[1].mergeCommit?.oid.hasPrefix("6af21769") == true && summaries[1].isCrossRepository)
        #expect(GHCommandClient.isSHA(summaries[0].headRefOid) && !GHCommandClient.isSHA("c9a5b05"))
        let started = ContinuousClock.now
        await #expect(throws: BrowserError.self) {
            try await TimedCommand.run(CommandRunner(), URL(filePath: "/bin/sleep"), arguments: ["20"], directory: URL(filePath: "/tmp"), timeout: .milliseconds(300))
        }
        #expect(started.duration(to: .now) < .seconds(5))
    }

    @Test func opensAPullRequestBrowsesAfterTogglesBeforeAndExits() async throws {
        // Fixture creation runs git synchronously; keep it off the main actor so
        // other suites' main-actor timers are not starved while it works.
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let client = FakeGitHubClient(summaries: [1: fixture.summary(number: 1)], mergeBase: fixture.baseSHA)
        let (model, _) = try Self.model(fixture, client: client)
        model.openRepository(fixture.attached)
        try await Self.waitUntil { !model.isOpening }
        #expect(model.attachedRoot == fixture.attached)
        try await Self.waitUntil { model.pullRequests.listPhase == .loaded }
        #expect(model.pullRequests.recent.map(\.number) == [1])
        model.openFile("src/lib.rs")
        try await Self.waitUntil { !model.isLoadingSource }
        #expect(model.source?.revision == nil)

        // Source Files Only follows each browsed snapshot's own listing.
        model.sourceFilters.sourceFilesOnly = true
        #expect(model.fileTree.first { $0.path == "src" }?.children?.map(\.path) == ["src/lib.rs", "src/old.rs"])
        model.openPullRequest(1)
        try await Self.waitUntil { model.review != nil && !model.isOpening && model.repository != nil }
        #expect(model.fileTree.map(\.path) == ["src", "uni.rs"])
        #expect(model.fileTree.first { $0.path == "src" }?.children?.map(\.path) == ["src/lib.rs", "src/new.rs"],
                "the head snapshot's tree, not the attached checkout's")
        let review = try #require(model.review)
        #expect(review.headSHA == fixture.headSHA && review.baseSHA == fixture.baseSHA)
        #expect(model.repository?.root == review.headRoot, "the browsed repository is the head snapshot")
        #expect(model.attachedRoot == fixture.attached, "the attached identity survives")
        #expect(model.mode == .changes)
        #expect(model.history.current == nil, "a review starts with fresh history")
        #expect(Set(review.changes.map(\.path)).contains("src/new.rs"))
        #expect(review.availableRevisions(for: "src/old.rs") == [.before])
        #expect(review.availableRevisions(for: "src/new.rs") == [.after])
        #expect(review.availableRevisions(for: "src/lib.rs") == [.before, .after])
        #expect(review.availableRevisions(for: "Cargo.toml") == [.after], "unchanged paths exist only as After bytes")

        // After: the head bytes, with highlights once the hunks arrive.
        model.openFile("src/lib.rs")
        try await Self.waitUntil { model.source?.revision == .after && !model.isLoadingSource }
        #expect(model.source?.text.contains("pub fn c()") == true)
        try await Self.waitUntil { model.reviewHighlights != nil }
        #expect(model.reviewHighlights?.lineRanges == [6..<12], "git's minimal diff: one replaced line, six added, the closing brace kept")
        #expect(model.reviewHighlights?.revision == .after)
        try await Self.waitUntil { model.syntax != nil }
        let changed = model.changedCallableIDs
        let names = Set(model.syntax!.symbols.filter { changed.contains($0.id) }.map(\.name))
        #expect(names == ["b", "c"], "only the callables containing added lines are marked")
        #expect(model.revisionControl?.available == [.before, .after])
        #expect(model.revisionControl?.status == "Modified")

        // Toggle to Before at the corresponding line; history records the exact After caret.
        model.caretMoved(to: model.source!.byteOffset(line: 10))
        model.toggleRevision()
        try await Self.waitUntil { model.source?.revision == .before && !model.isLoadingSource }
        #expect(model.source?.text.contains("pub fn c()") == false)
        #expect(model.currentLine == 6, "After line 10 (inside the hunk) maps to the Before hunk's first line")
        #expect(model.semantics.documentSemantics == nil)
        #expect(model.semanticAvailability == .revisionNotIndexed)
        try await Self.waitUntil { model.reviewHighlights?.revision == .before }
        #expect(model.reviewHighlights?.lineRanges == [6..<7])
        #expect(model.positions.keys.contains("after:src/lib.rs") == false || model.positions["after:src/lib.rs"] != nil)
        model.goBack()
        try await Self.waitUntil { model.source?.revision == .after && !model.isLoadingSource }
        #expect(model.currentLine == 10)
        #expect(model.history.current?.revision == .after)

        // A deleted file opens Before only; an added file After only; the rename pairs its paths.
        let deleted = try #require(review.change(touching: "src/old.rs"))
        model.openChange(deleted)
        try await Self.waitUntil { model.source?.path == "src/old.rs" && !model.isLoadingSource }
        #expect(model.source?.revision == .before)
        #expect(model.revisionControl?.available == [.before] && model.revisionControl?.status == "Deleted")
        let renamed = try #require(review.change(touching: "docs/readme.md"))
        model.openChange(renamed)
        try await Self.waitUntil { model.source?.path == "docs/README.md" && !model.isLoadingSource }
        model.setRevision(.before)
        try await Self.waitUntil { model.source?.path == "docs/readme.md" && model.source?.revision == .before && !model.isLoadingSource }
        #expect(model.revisionControl?.status.hasPrefix("Renamed") == true)
        // Sidebar filters do not navigate or rewrite the canonical PR, even
        // while an excluded renamed Markdown document is open in Before.
        let departure = model.navigationTarget
        let history = model.history.current
        let revision = model.navigationRevision
        model.sourceFilters = SourceFilters(hidesTests: true, sourceFilesOnly: true)
        let filtered = ReviewChangesPresentation(changes: review.changes, filters: model.sourceFilters)
        #expect(filtered.selectionID(path: model.source?.path, revision: model.currentRevision) == nil)
        #expect(model.source?.path == "docs/readme.md" && model.currentRevision == .before)
        #expect(model.navigationTarget == departure && model.history.current == history && model.navigationRevision == revision)
        #expect(model.review?.changes == review.changes)
        model.clearSourceFilters()
        #expect(model.navigationTarget == departure && model.navigationRevision == revision)

        // A search hit always opens After even when the path is set to Before.
        model.navigate(toSearchResult: SourceLocation(path: "docs/README.md", byteOffset: 0))
        try await Self.waitUntil { model.source?.revision == .after && model.source?.path == "docs/README.md" && !model.isLoadingSource }

        // Local checkout: the attached folder returns, with review state gone.
        model.exitPullRequest()
        try await Self.waitUntil { !model.isOpening && model.repository != nil }
        #expect(model.review == nil)
        #expect(model.repository?.root == fixture.attached)
        #expect(model.mode == .files)
        #expect(model.reviewHighlights == nil)
        #expect(model.pullRequests.recent.map(\.number) == [1], "the recent list survives leaving a review")
        #expect(model.fileTree.first { $0.path == "src" }?.children?.map(\.path) == ["src/lib.rs", "src/old.rs"])
    }

    @Test func changedBlockJumpsRevealTestsAndBackUsesCaretNotPassiveScroll() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let pair = try await Task.detached { () -> (String, String) in
            try GitFixture.run(["checkout", "-q", "-b", "blocks", fixture.baseSHA], in: fixture.origin)
            var lines = ["fn production() {", "    let value = 1;", "    consume(value);", "}"]
            lines += (5...19).map { "// stable \($0)" }
            lines += ["#[cfg(test)]", "fn helper() {", "    let value = 1;", "}"]
            lines += (24...35).map { "// stable \($0)" }
            try GitFixture.write(lines.joined(separator: "\n"), to: fixture.origin.appending(path: "src/blocks.rs"))
            try GitFixture.run(["add", "-A"], in: fixture.origin)
            try GitFixture.run(["commit", "-q", "-m", "blocks base"], in: fixture.origin)
            let base = try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin)
            lines[1] = "    let value = 2;"
            lines[21] = "    let value = 2;"
            lines.removeLast()
            try GitFixture.write(lines.joined(separator: "\n") + "\n", to: fixture.origin.appending(path: "src/blocks.rs"))
            try GitFixture.run(["commit", "-q", "-am", "blocks head"], in: fixture.origin)
            return (base, try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin))
        }.value
        let summary = PullRequestSummary(number: 1, title: "Blocks", state: "OPEN", baseRefName: "blocks", baseRefOid: pair.0,
                                         headRefName: "blocks", headRefOid: pair.1, isCrossRepository: false, updatedAt: .now,
                                         mergeCommit: nil, author: nil)
        let client = FakeGitHubClient(summaries: [1: summary], mergeBase: pair.0)
        let (model, _) = try Self.model(fixture, client: client)
        model.openRepository(fixture.attached)
        try await Self.waitUntil { !model.isOpening }
        model.openPullRequest(1)
        try await Self.waitUntil { model.review != nil && !model.isOpening && model.repository != nil }
        let change = try #require(model.review?.change(touching: "src/blocks.rs"))
        model.openChange(change)
        try await Self.waitUntil { model.syntax?.path == "src/blocks.rs" && model.reviewHighlights != nil }
        model.sourceFilters.hidesTests = true
        let source = try #require(model.source)
        let departure = source.location(atByte: source.byteOffset(line: 3) + 5)
        model.caretMoved(to: departure.byteOffset)
        model.updatePosition(path: source.path, byteOffset: source.byteOffset(line: 30), line: 30)
        #expect(model.canGoToNextChange && model.canGoToPreviousChange)
        let invalidated = ObservationFlag()
        withObservationTracking {
            _ = model.canGoToNextChange
            _ = model.canGoToPreviousChange
        } onChange: { invalidated.mark() }
        model.updatePosition(path: source.path, byteOffset: 0, line: 1)
        #expect(!invalidated.isSet, "passive scrolling does not invalidate caret availability")
        model.caretMoved(to: departure.byteOffset + 1)
        #expect(invalidated.isSet, "same-line whitespace caret movement invalidates availability")
        model.caretMoved(to: departure.byteOffset)
        model.goToNextChange()
        #expect(model.navigationTarget == source.location(atByte: source.byteOffset(line: 22)))
        #expect(!model.revealedTestRegions.isEmpty)
        model.goBack()
        #expect(model.navigationTarget == departure)
        model.caretMoved(to: source.byteOffset(line: 2) + 5)
        #expect(!model.canGoToPreviousChange)
        model.goToNextChange()
        #expect(model.currentLine == 22, "inside first block skips to second block")
        model.goToNextChange()
        #expect(model.navigationTarget == source.location(atByte: source.data.count), "EOF deletion anchor remains reachable")
        #expect(!model.canGoToNextChange && model.canGoToPreviousChange)
        #expect(model.reviewHighlights?.anchors.last == source.lineCount)
        #expect(model.reviewHighlights?.lineRanges.contains(where: { $0.contains(source.lineCount) }) == false)
        let valid = try #require(model.reviewHighlights)
        model.reviewHighlights = ReviewHighlights(path: valid.path, revision: .before, sourceIdentity: valid.sourceIdentity,
                                                  lineRanges: valid.lineRanges, byteRanges: valid.byteRanges, anchors: valid.anchors, isBinary: false)
        #expect(!model.canGoToNextChange && !model.canGoToPreviousChange, "same bytes with stale revision cannot navigate")
        model.reviewHighlights = ReviewHighlights(path: valid.path, revision: valid.revision,
            sourceIdentity: SourceContentIdentity(Data("stale".utf8)), lineRanges: valid.lineRanges,
            byteRanges: valid.byteRanges, anchors: valid.anchors, isBinary: false)
        #expect(model.changeBlockNavigation == nil, "stale content cannot navigate")
        model.reviewHighlights = ReviewHighlights(path: valid.path, revision: valid.revision,
            sourceIdentity: valid.sourceIdentity, lineRanges: [], byteRanges: [], anchors: valid.anchors, isBinary: true)
        #expect(model.changeBlockNavigation == nil, "binary cannot navigate")
        model.reviewHighlights = nil
        #expect(model.changeBlockNavigation == nil, "pending/unavailable hunks disable directions")
        model.refreshReviewHighlights()
        model.setRevision(.before)
        try await Self.waitUntil { model.source?.revision == .before && model.reviewHighlights?.revision == .before }
        let before = try #require(model.source)
        model.caretMoved(to: before.byteOffset(line: 3))
        model.goToNextChange()
        #expect(model.navigationTarget?.revision == .before && model.currentLine == 22)
    }

    @Test func errorsAndSupersededLoadsNeverPublishStaleReviews() async throws {
        // Fixture creation runs git synchronously; keep it off the main actor so
        // other suites' main-actor timers are not starved while it works.
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let client = FakeGitHubClient(summaries: [1: fixture.summary(number: 1)], mergeBase: fixture.baseSHA)
        client.pullRequestDelay = .milliseconds(400)
        let (model, _) = try Self.model(fixture, client: client)
        model.openRepository(fixture.attached)
        try await Self.waitUntil { !model.isOpening }
        // Unknown number: the error is shown and the checkout stays open.
        model.openPullRequest(999)
        try await Self.waitUntil { model.pullRequests.loadError != nil }
        #expect(model.pullRequests.loadError?.contains("999") == true)
        #expect(model.pullRequests.failedNumber == 999)
        let calls = client.viewCalls
        model.pullRequests.retryFailedReview()
        #expect(model.pullRequests.loadError == nil)
        try await Self.waitUntil { model.pullRequests.loadError != nil }
        #expect(client.viewCalls == calls + 1, "visible retry reopens the failed number")
        // Exiting a pending retry on the local checkout clears the failure and
        // cannot publish a late error or discard the current reader/history.
        model.openFile("src/lib.rs")
        try await Self.waitUntil { model.source?.path == "src/lib.rs" && !model.isLoadingSource }
        let departure = model.history.current
        model.pullRequests.retryFailedReview()
        #expect(model.pullRequests.isLoading)
        model.exitPullRequest()
        #expect(!model.pullRequests.isLoading && model.pullRequests.loadError == nil)
        #expect(model.pullRequests.failedNumber == nil)
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.pullRequests.loadError == nil && model.review == nil)
        #expect(model.source?.path == "src/lib.rs" && model.history.current == departure)

        #expect(model.review == nil && model.repository?.root == fixture.attached)
        // A load superseded by a repository switch must not land.
        model.openPullRequest(1)
        #expect(model.pullRequests.isLoading)
        let other = fixture.directory.appending(path: "other", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: other.appending(path: "a.txt"))
        model.openRepository(other)
        try await Self.waitUntil { !model.isOpening }
        try await Task.sleep(for: .seconds(1))
        #expect(model.review == nil)
        #expect(model.repository?.root == other.resolvingSymlinksInPath())
        #expect(model.pullRequests.listPhase == .unavailable("Pull requests need a Git repository with a GitHub origin."))
        // A load superseded by another PR number keeps only the latest.
        model.openRepository(fixture.attached)
        try await Self.waitUntil { !model.isOpening }
        client.summaries[2] = fixture.summary(number: 2)
        client.mergeBases["\(fixture.mainSHA)...\(fixture.headSHA)"] = fixture.baseSHA
        model.openPullRequest(1)
        model.openPullRequest(2)
        try await Self.waitUntil(.seconds(60)) { model.review != nil && !model.isOpening }
        #expect(model.review?.number == 2)
        try await Task.sleep(for: .milliseconds(600))
        #expect(model.review?.number == 2)
        // Reloading inside a review keeps the review and the head snapshot.
        model.refresh()
        try await Self.waitUntil { !model.pullRequests.isLoading && !model.isOpening && model.repository != nil }
        #expect(model.review?.number == 2 && model.repository?.root == model.review?.headRoot)
    }
}
