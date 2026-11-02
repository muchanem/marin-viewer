import Testing
@testable import Radiology

struct ReviewChangesPresentationTests {
    private func change(_ path: String, old: String? = nil, status: FileChange.Status = .modified) -> FileChange {
        FileChange(path: path, oldPath: old, status: status, beforeBlob: "before", afterBlob: "after", additions: 2, deletions: 1)
    }

    @Test func sharedFiltersKeepOrderAndOnlyVisibleTotals() {
        let rows = [change("README.md"), change("src/a.rs"), change("tests/a.rs"),
                    change("target/generated.rs"), change("scripts/test_api.py"), change("src/deleted.kt", status: .deleted)]
        let source = ReviewChangesPresentation(changes: rows, filters: .init(sourceFilesOnly: true))
        #expect(source.changes.map(\.path) == ["src/a.rs", "tests/a.rs", "scripts/test_api.py", "src/deleted.kt"])
        let tests = ReviewChangesPresentation(changes: rows, filters: .init(hidesTests: true))
        #expect(tests.changes.map(\.path) == ["README.md", "src/a.rs", "target/generated.rs", "src/deleted.kt"])
        let both = ReviewChangesPresentation(changes: rows, filters: .init(hidesTests: true, sourceFilesOnly: true))
        #expect(both.changes.map(\.path) == ["src/a.rs", "src/deleted.kt"])
        #expect(both.totalCount == 6 && both.additions == 4 && both.deletions == 2)
        #expect(rows.count == 6, "canonical diff data is not modified")
    }

    @Test func renameAcceptsEitherAvailablePathAndDeletionUsesBefore() {
        let rows = [change("docs/old.md", old: "src/old.rs", status: .renamed(similarity: 70)),
                    change("src/new.rs", old: "docs/new.md", status: .renamed(similarity: 70)),
                    change("tests/test.rs", old: "src/moved.rs", status: .renamed(similarity: 100)),
                    change("docs/gone.md", status: .deleted), change("src/gone.rs", status: .deleted)]
        let visible = ReviewChangesPresentation(changes: rows, filters: .init(hidesTests: true, sourceFilesOnly: true))
        #expect(visible.changes.map(\.path) == ["docs/old.md", "src/new.rs", "tests/test.rs", "src/gone.rs"])
        #expect(visible.selectionID(path: "src/old.rs", revision: .before) == "docs/old.md")
        #expect(visible.selectionID(path: "docs/old.md", revision: .after) == "docs/old.md")
        #expect(visible.selectionID(path: "docs/gone.md", revision: .before) == nil)
        #expect(visible.selectionID(path: "src/gone.rs", revision: .after) == nil)
    }

    @Test func filteredEmptyDiffersFromNoChangesAndResetRestoresSelection() {
        let rows = [change("README.md", status: .added)]
        let hidden = ReviewChangesPresentation(changes: rows, filters: .init(sourceFilesOnly: true))
        #expect(hidden.isFilteredEmpty && !hidden.isGenuinelyEmpty)
        #expect(hidden.selectionID(path: "README.md", revision: .after) == nil)
        let reset = ReviewChangesPresentation(changes: rows, filters: .init())
        #expect(reset.selectionID(path: "README.md", revision: .after) == "README.md")
        let empty = ReviewChangesPresentation(changes: [], filters: .init(sourceFilesOnly: true))
        #expect(empty.isGenuinelyEmpty && !empty.isFilteredEmpty)
    }
}
