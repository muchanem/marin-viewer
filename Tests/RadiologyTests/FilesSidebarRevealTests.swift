import SwiftUI
import Testing
@testable import Radiology

@MainActor
struct FilesSidebarRevealTests {
    private func table(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews { if let table = table(in: child) { return table } }
        return nil
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(condition(), "timed out")
    }

    @Test func presentationsRevealFilteredAndBeforeOnlyFilesWithoutChangingFilters() {
        let root = URL(filePath: "/tmp/repo")
        let files = ["src/main.swift", "tests/nested/Spec.swift", "docs/guide.md"].map(RepositoryFile.init(path:))
        let repo = RepositorySnapshot(root: root, files: files, tree: FileNode.tree(files: files), isGit: false)
        let filters = SourceFilters(hidesTests: true, sourceFilesOnly: true)
        let visible = files.filter { filters.includes($0.path) }
        let current = FilesSidebarPresentation(repository: repo, tree: FileNode.tree(files: visible), files: [],
                                               filters: filters, path: "tests/nested/Spec.swift", loadedPath: "tests/nested/Spec.swift", isBeforePath: false)
        #expect(current.addsTreeException && current.addsFilterException)
        #expect(current.tree.map(\.path) == ["src", "tests"])
        #expect(current.files.map(\.path) == ["tests/nested/Spec.swift"])
        #expect(visible.map(\.path) == ["src/main.swift"])
        let before = FilesSidebarPresentation(repository: repo, tree: repo.tree, files: files, filters: SourceFilters(),
                                              path: "old/deleted.swift", loadedPath: nil, isBeforePath: true)
        #expect(before.currentFileOutsideSnapshot && before.tree.map(\.path).contains("old"))
        #expect(before.files.map(\.path).contains("old/deleted.swift"))
        let missing = FilesSidebarPresentation(repository: repo, tree: repo.tree, files: files, filters: SourceFilters(),
                                               path: "missing.swift", loadedPath: nil, isBeforePath: false)
        #expect(missing.currentFile == nil && !missing.addsTreeException)
    }

    @Test func expandingAncestorsPreservesOtherFolders() {
        let expansion = FileTreeExpansion()
        expansion.setExpanded(true, path: "other")
        expansion.reveal("a/b/c/file.swift")
        #expect(expansion.expandedPaths == ["other", "a", "a/b", "a/b/c"])
        expansion.reveal("top.swift")
        #expect(!expansion.isExpanded("top.swift"))
    }

    @Test func nativeFilesListTracksBookmarksAndSearchAndPreservesTheirCaret() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-files-reveal-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let content = "func work() {\n    let value = 1\n}\n"
        let paths = ["top.swift"] + (0..<90).map { "a/deep/file\(String($0).leftPaddedForTests).swift" }
            + (0..<90).map { "b/deep/file\(String($0).leftPaddedForTests).swift" }
        for path in paths {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        let preferences = try #require(UserDefaults(suiteName: "RadiologyFilesTests.\(UUID().uuidString)"))
        let model = AppModel(preferences: preferences)
        await model.openRepository(root, selecting: "a/deep/file055.swift")
        await model.awaitCurrentSourceLoad()
        model.caretMoved(to: 17)
        model.toggleCurrentBookmark()
        model.openFile("top.swift")
        await model.awaitCurrentSourceLoad()
        model.fileTreeExpansion.reset()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 420), styleMask: [.titled], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: RepositorySidebar().environment(model))
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await waitUntil { self.table(in: host) != nil }
        model.goToBookmark(slot: 0)
        try await waitUntil { model.source?.path == "a/deep/file055.swift" && !model.isLoadingSource }
        try await waitUntil { host.layoutSubtreeIfNeeded(); return self.table(in: host)?.selectedRow ?? -1 > 40 }
        let files = try #require(self.table(in: host))
        let scroll = try #require(files.enclosingScrollView)
        let row = files.selectedRow
        #expect(model.fileTreeExpansion.isExpanded("a") && model.fileTreeExpansion.isExpanded("a/deep"))
        #expect(abs(files.rect(ofRow: row).midY - scroll.contentView.bounds.midY) <= files.rowHeight + 2)
        #expect(model.currentCaretLocation?.byteOffset == 17)

        // Manual list browsing is not undone by ordinary source caret moves.
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        model.caretMoved(to: 18)
        try await Task.sleep(for: .milliseconds(60))
        #expect(scroll.contentView.bounds.minY < 2)
        // An explicit jump in the same file does reveal it again.
        model.navigate(to: try #require(model.source).location(atByte: 19))
        try await waitUntil { abs(files.rect(ofRow: files.selectedRow).midY - scroll.contentView.bounds.midY) <= files.rowHeight + 2 }

        // Returning from Search mounts a new Files view and must reveal the
        // current result without converting its exact jump into an openFile.
        model.mode = .search
        let destination = Radiology.SourceLocation(path: "b/deep/file044.swift", byteOffset: 19)
        model.navigate(toSearchResult: destination)
        await model.awaitCurrentSourceLoad()
        let navigation = model.navigationRevision
        let history = model.history.entries
        model.mode = .files
        try await waitUntil { host.layoutSubtreeIfNeeded(); return model.fileTreeExpansion.isExpanded("b/deep") && (self.table(in: host)?.selectedRow ?? -1) > 100 }
        let next = try #require(self.table(in: host))
        let nextScroll = try #require(next.enclosingScrollView)
        #expect(abs(next.rect(ofRow: next.selectedRow).midY - nextScroll.contentView.bounds.midY) <= next.rowHeight + 2)
        #expect(model.currentCaretLocation == destination && model.navigationRevision == navigation && model.history.entries == history)
    }

    @Test func nativeFilteredListRevealsBeforeOnlyPRFileAndKeepsItsRevision() async throws {
        let fixture = try await Task.detached { try GitFixture.make() }.value
        defer { fixture.remove() }
        let domain = "RadiologyFilesTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let cache = IndexCache(root: fixture.directory.appending(path: "cache"))
        let client = FakeGitHubClient(summaries: [1: fixture.summary(number: 1)], mergeBase: fixture.baseSHA)
        let model = AppModel(preferences: preferences,
                             semantics: SemanticModel(service: SemanticIndexService(indexers: [], cache: cache, tools: ToolDirectory(url: fixture.directory.appending(path: "tools")))),
                             pullRequests: PullRequestModel(client: client, workingTreeCache: cache))
        await model.openRepository(fixture.attached, selecting: nil, pullRequest: 1)
        try await waitUntil { !model.isOpening && model.review != nil && model.repository != nil }
        let destination = Radiology.SourceLocation(path: "src/old.rs", byteOffset: 5, revision: .before)
        model.navigate(to: destination)
        await model.awaitCurrentSourceLoad()
        model.mode = .files
        model.sourceFilters = SourceFilters(hidesTests: true, sourceFilesOnly: true)
        model.fileQuery = "does-not-match"
        model.filterFiles()
        #expect(model.filteredFiles.isEmpty)
        let presentation = try #require(model.filesSidebarPresentation)
        #expect(presentation.currentFileOutsideSnapshot && presentation.addsTreeException && presentation.addsFilterException)
        #expect(presentation.files.map(\.path) == [destination.path])
        let navigation = model.navigationRevision
        let history = model.history.entries
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 420), styleMask: [.titled], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: RepositorySidebar().environment(model))
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await waitUntil { host.layoutSubtreeIfNeeded(); return self.table(in: host)?.selectedRow == 0 }
        #expect(model.fileTreeExpansion.isExpanded("src"))
        #expect(model.sourceFilters == SourceFilters(hidesTests: true, sourceFilesOnly: true) && model.fileQuery == "does-not-match")
        #expect(model.currentCaretLocation == destination && model.source?.revision == .before)
        #expect(model.navigationRevision == navigation && model.history.entries == history)
        model.fileQuery = ""
        model.filterFiles()
        try await waitUntil { host.layoutSubtreeIfNeeded(); return (self.table(in: host)?.selectedRow ?? -1) > 0 }
        #expect(model.currentCaretLocation == destination && model.navigationRevision == navigation)
    }
}

private extension String {
    var leftPaddedForTests: String { String(repeating: "0", count: max(0, 3 - count)) + self }
}
