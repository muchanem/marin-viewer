import Foundation
import Testing
@testable import Radiology

@Suite(.serialized) @MainActor
struct BookmarkNavigationTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition(), "timed out")
    }

    private func model(_ fixture: GitFixture, preferences: UserDefaults) -> AppModel {
        let cache = IndexCache(root: fixture.directory.appending(path: "bookmark-cache"))
        let service = SemanticIndexService(indexers: [], cache: cache, tools: ToolDirectory(url: fixture.directory.appending(path: "tools")))
        let client = FakeGitHubClient(summaries: [1: fixture.summary(number: 1)], mergeBase: fixture.baseSHA)
        client.summaries[2] = fixture.summary(number: 2)
        return AppModel(preferences: preferences, semantics: SemanticModel(service: service),
                        pullRequests: PullRequestModel(client: client, workingTreeCache: cache))
    }

    @Test func shortcutsUseReorderedBookmarksAndBackRestoresTheExactCaret() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.BookmarkNavigation." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = model(fixture, preferences: preferences)
        await model.openRepository(fixture.attached, selecting: "uni.rs")
        await model.awaitCurrentSourceLoad()
        let unicode = try #require(model.source)
        let byte = try #require(unicode.text.range(of: "= 1").map { unicode.text[..<$0.lowerBound].utf8.count })
        model.caretMoved(to: byte)
        model.updatePosition(path: unicode.path, byteOffset: 0, line: 1)
        model.toggleCurrentBookmark()
        #expect(model.isCurrentLocationBookmarked)
        let first = try #require(model.bookmarks.bookmark(at: 0))
        #expect(first.byteOffset == byte)
        model.openFile("src/lib.rs")
        await model.awaitCurrentSourceLoad()
        let lib = try #require(model.source)
        let departure = lib.location(atByte: lib.byteOffset(line: 2, column: 4))
        model.caretMoved(to: departure.byteOffset)
        model.toggleCurrentBookmark()
        let second = try #require(model.bookmarks.bookmark(at: 1))
        model.goToBookmark(slot: 0)
        try await waitUntil { model.source?.path == first.path && !model.isLoadingSource }
        #expect(model.currentCaretLocation == first.location)
        model.goBack()
        await model.awaitCurrentSourceLoad()
        #expect(model.currentCaretLocation == departure)
        model.bookmarks.move(second.id, to: 0)
        model.goToBookmark(slot: 1)
        try await waitUntil { model.source?.path == first.path && !model.isLoadingSource }
        #expect(model.currentCaretLocation == first.location)
        model.goToBookmark(slot: 0)
        try await waitUntil { model.source?.path == second.path && !model.isLoadingSource }
        #expect(model.currentCaretLocation == second.location)
        let revision = model.navigationRevision
        model.goToBookmark(slot: 10)
        #expect(model.navigationRevision == revision)
        let relaunched = self.model(fixture, preferences: preferences)
        await relaunched.openRepository(fixture.attached, selecting: nil)
        #expect(relaunched.bookmarks.entries.map(\.id) == [second.id, first.id])
        // Inserting source above the bookmark relocates its line while its ID,
        // order and shortcut stay fixed; toggling at the new caret removes it.
        try Data(("// inserted\n" + unicode.text).utf8).write(to: fixture.attached.appending(path: unicode.path))
        model.goToBookmark(slot: 1)
        try await waitUntil { model.source?.path == first.path && !model.isLoadingSource }
        #expect(model.currentCaretLocation?.byteOffset == byte + "// inserted\n".utf8.count)
        #expect(model.bookmarks.bookmark(at: 1)?.id == first.id)
        #expect(model.bookmarks.bookmark(at: 1)?.line == first.line + 1)
        #expect(model.isCurrentLocationBookmarked)
        model.toggleCurrentBookmark()
        #expect(model.bookmarks.entries.map(\.id) == [second.id])
    }

    @Test func checkoutEachPRAndAnotherRepositoryKeepIndependentListsAndRevisions() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.BookmarkNavigation." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = model(fixture, preferences: preferences)
        await model.openRepository(fixture.attached, selecting: "uni.rs")
        await model.awaitCurrentSourceLoad()
        model.toggleCurrentBookmark()
        let local = try #require(model.bookmarks.entries.first)
        await model.openRepository(fixture.attached, selecting: "uni.rs", pullRequest: 1)
        try await waitUntil { model.review?.number == 1 && !model.isOpening && model.source?.revision == .after }
        #expect(model.bookmarks.entries.isEmpty)
        #expect(model.bookmarks.scope == BookmarkScope(root: fixture.attached, pullRequest: 1))
        #expect(model.repository?.root != fixture.attached)
        model.caretMoved(to: try #require(model.source).byteOffset(line: 2, column: 4))
        model.toggleCurrentBookmark()
        let after = try #require(model.bookmarks.entries.first)
        model.setRevision(.before)
        await model.awaitCurrentSourceLoad()
        #expect(model.source?.revision == .before)
        model.caretMoved(to: try #require(model.source).byteOffset(line: 2, column: 4))
        model.toggleCurrentBookmark()
        let before = try #require(model.bookmarks.bookmark(at: 1))
        #expect(after.revision == .after && before.revision == .before)
        model.openPullRequest(2)
        try await waitUntil { model.review?.number == 2 && !model.isOpening && model.repository != nil }
        #expect(model.bookmarks.entries.isEmpty)
        model.openFile("src/lib.rs")
        await model.awaitCurrentSourceLoad()
        model.toggleCurrentBookmark()
        model.openPullRequest(1)
        try await waitUntil { model.review?.number == 1 && !model.isOpening && model.repository != nil }
        #expect(model.bookmarks.entries.map(\.id) == [after.id, before.id])
        model.goToBookmark(slot: 1)
        try await waitUntil { model.source?.revision == .before && !model.isLoadingSource }
        #expect(model.currentCaretLocation == before.location)
        model.goToBookmark(slot: 0)
        try await waitUntil { model.source?.revision == .after && !model.isLoadingSource }
        #expect(model.currentCaretLocation == after.location)
        model.goBack()
        await model.awaitCurrentSourceLoad()
        #expect(model.currentCaretLocation == before.location)
        model.exitPullRequest()
        try await waitUntil { !model.isOpening && model.repository != nil && model.review == nil }
        #expect(model.bookmarks.entries.map(\.id) == [local.id])
        await model.openRepository(fixture.origin, selecting: nil)
        #expect(model.bookmarks.entries.isEmpty)
        await model.openRepository(fixture.attached, selecting: nil)
        #expect(model.bookmarks.entries.map(\.id) == [local.id])
    }

    @Test func missingFilesAndSupersededJumpsLeaveTheReaderAlone() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyTests.BookmarkNavigation." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = model(fixture, preferences: preferences)
        await model.openRepository(fixture.attached, selecting: "uni.rs")
        await model.awaitCurrentSourceLoad()
        model.toggleCurrentBookmark()
        model.openFile("src/lib.rs")
        await model.awaitCurrentSourceLoad()
        let departure = model.currentCaretLocation
        let history = model.history.entries
        try FileManager.default.removeItem(at: fixture.attached.appending(path: "uni.rs"))
        model.goToBookmark(slot: 0)
        try await waitUntil { model.bookmarks.navigationError != nil }
        #expect(model.currentCaretLocation == departure && model.history.entries == history)
        #expect(model.bookmarks.entries.count == 1)
        model.goToBookmark(slot: 0)
        model.openRepository(fixture.origin)
        try await waitUntil { !model.isOpening && model.repository != nil }
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.bookmarks.navigationError == nil && model.bookmarks.entries.isEmpty)
        #expect(model.source == nil && model.repository?.root == fixture.origin)
    }
}
