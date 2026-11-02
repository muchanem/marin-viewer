import Testing
@testable import Radiology

struct QuickFileSearchTests {
    @Test func orderedSubsequenceFindsTheUsersExampleAndRejectsOutOfOrderText() async {
        let files = [RepositoryFile(path: "engine/rust/engine-foo.rs"), RepositoryFile(path: "notes/green.rs")]
        let match = await QuickFileSearch.search("engrs", in: files)
        #expect(match.files.map(\.path) == ["engine/rust/engine-foo.rs"])
        #expect((await QuickFileSearch.search("srgne", in: files)).files.isEmpty)
        #expect((await QuickFileSearch.search("ENGRS", in: files)).files.map(\.path) == ["engine/rust/engine-foo.rs"])
    }

    @Test func rankingFavorsFilenameExactPrefixAndContiguousBeforeGappyAndPathOnly() async {
        let files = [
            RepositoryFile(path: "z/scan.swift"),
            RepositoryFile(path: "scan-tools/other.swift"),
            RepositoryFile(path: "a/scanner.swift"),
            RepositoryFile(path: "b/rescan.swift"),
            RepositoryFile(path: "c/source-canary.swift"),
        ]
        let result = await QuickFileSearch.search("scan", in: files)
        #expect(result.files.map(\.path) == ["z/scan.swift", "a/scanner.swift", "b/rescan.swift", "c/source-canary.swift", "scan-tools/other.swift"])
    }

    @Test func unicodeCaseFoldingAndStablePathDisambiguationWork() async {
        let files = [RepositoryFile(path: "b/Café.swift"), RepositoryFile(path: "a/CAFÉ.swift")]
        let result = await QuickFileSearch.search("cafe", in: files)
        #expect(result.files.map(\.path) == ["a/CAFÉ.swift", "b/Café.swift"])
    }

    @Test func visibleResultsAreBoundedButTotalCountRemainsTruthful() async {
        let files = (0..<140).map { RepositoryFile(path: String(format: "src/match-%03d.rs", $0)) }
        let result = await QuickFileSearch.search("match", in: files)
        #expect(result.files.count == 100)
        #expect(result.totalCount == 140)
        #expect(result.isLimited)
    }

    @Test func selectionResetsAndClampsAcrossResultChanges() {
        let files = [RepositoryFile(path: "a.rs"), RepositoryFile(path: "b.rs"), RepositoryFile(path: "c.rs")]
        var selection = QuickFileSelection()
        selection.reset(for: files)
        #expect(selection.path == "a.rs")
        selection.move(1, in: files)
        selection.move(9, in: files)
        #expect(selection.path == "c.rs")
        selection.move(-9, in: files)
        #expect(selection.path == "a.rs")
        selection.reset(for: [])
        #expect(selection.path == nil)
    }
}
