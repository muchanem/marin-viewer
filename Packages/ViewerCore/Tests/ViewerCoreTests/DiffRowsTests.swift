import Foundation
import Testing
@testable import ViewerCore

struct DiffRowsTests {
    /// The rows equal `demo/pr10640.json`'s `lines`, built by `demo/extract.py`
    /// from the same `git diff -U100000` output.
    @Test(arguments: [
        ("src_shellbox_backends_local_machine.py.diff", "lib/shellbox/src/shellbox/backends/local/machine.py", FileChangeStatus.modified),
        ("src_shellbox_http_service.py.diff", "lib/shellbox/src/shellbox/http_service.py", .added),
        ("README.md.diff", "lib/shellbox/README.md", .modified),
        ("src_shellbox_machine.py.diff", "lib/shellbox/src/shellbox/machine.py", .modified),
    ])
    func rowsMatchTheDemoData(fixture: String, path: String, status: FileChangeStatus) throws {
        let diff = try DiffRows.parse(try Fixtures.text("pr10640/" + fixture))
        let expected = try Fixtures.expectedRows(path)
        #expect(diff.path == path)
        #expect(diff.status == status)
        #expect(diff.oldPath == (status == .added ? nil : path))
        #expect(diff.rows.count == expected.count)
        let mismatch = zip(diff.rows, expected).enumerated().first { $0.element.0 != $0.element.1 }
        #expect(mismatch == nil, "first mismatch at row \(mismatch?.offset ?? -1): \(String(describing: mismatch?.element))")
    }

    @Test func realDataCountsAndLookup() throws {
        let diff = try DiffRows.parse(try Fixtures.text("pr10640/src_shellbox_backends_local_machine.py.diff"))
        #expect(diff.rows.count == 1538)
        #expect(diff.rows.compactMap(\.newLine).last == 1281, "@@ -1,790 +1,1281 @@")
        #expect(diff.rows.compactMap(\.oldLine).last == 790)
        #expect(diff.additions + diff.rows.count { $0.kind == .context } == 1281)
        let row = try #require(diff.rowIndex(forNewLine: 327))
        #expect(diff.rows[row].newLine == 327)
        #expect(diff.rowIndex(forNewLine: 1282) == nil)
    }

    @Test func addedAndDeletedFiles() throws {
        let added = try DiffRows.parse(try Fixtures.text("edge/added.diff"))
        #expect(added.status == .added)
        #expect(added.oldPath == nil && added.newPath == "added.txt" && added.newMode == "100644")
        // Body lines that look like headers stay rows.
        #expect(added.rows.map(\.text) == ["fresh", "- dash line", "-- double", "+++ plus", "@@ at"])
        #expect(added.rows.allSatisfy { $0.kind == .added && $0.oldLine == nil })
        #expect(added.rows.map(\.newLine) == [1, 2, 3, 4, 5])

        let deleted = try DiffRows.parse(try Fixtures.text("edge/deleted.diff"))
        #expect(deleted.status == .deleted)
        #expect(deleted.oldPath == "gone.txt" && deleted.newPath == nil && deleted.path == "gone.txt")
        #expect(deleted.rows == [
            DiffRow(kind: .deleted, oldLine: 1, newLine: nil, text: "one"),
            DiffRow(kind: .deleted, oldLine: 2, newLine: nil, text: "two"),
            DiffRow(kind: .deleted, oldLine: 3, newLine: nil, text: "three"),
        ])
        #expect(deleted.deletions == 3 && deleted.additions == 0)

        let empty = try DiffRows.parse(try Fixtures.text("edge/empty.diff"))
        #expect(empty.status == .added && empty.newPath == "empty.txt" && empty.rows.isEmpty)
    }

    @Test func binaryRenamedAndModeOnly() throws {
        let binary = try DiffRows.parse(try Fixtures.text("edge/binary.diff"))
        #expect(binary.isBinary && binary.rows.isEmpty)
        #expect(binary.status == .modified && binary.path == "img.bin")

        let renamed = try DiffRows.parse(try Fixtures.text("edge/renamed.diff"))
        #expect(renamed.status == .renamed && renamed.similarity == 78)
        #expect(renamed.oldPath == "old_name.txt" && renamed.newPath == "new_name.txt")
        #expect(renamed.rows == [
            DiffRow(kind: .context, oldLine: 1, newLine: 1, text: "alpha"),
            DiffRow(kind: .deleted, oldLine: 2, newLine: nil, text: "beta"),
            DiffRow(kind: .added, oldLine: nil, newLine: 2, text: "BETA"),
            DiffRow(kind: .context, oldLine: 3, newLine: 3, text: "gamma"),
            DiffRow(kind: .context, oldLine: 4, newLine: 4, text: "delta"),
        ])

        let pure = try DiffRows.parse(try Fixtures.text("edge/pure-rename.diff"))
        #expect(pure.status == .renamed && pure.similarity == 100 && pure.rows.isEmpty)
        #expect(pure.oldPath == "new_name.txt" && pure.newPath == "pure.txt")
        #expect(DiffRows.unchanged("alpha\nBETA\n") == [
            DiffRow(kind: .context, oldLine: 1, newLine: 1, text: "alpha"),
            DiffRow(kind: .context, oldLine: 2, newLine: 2, text: "BETA"),
        ])

        let mode = try DiffRows.parse(try Fixtures.text("edge/mode.diff"))
        #expect(mode.status == .modified && mode.rows.isEmpty)
        #expect(mode.oldMode == "100644" && mode.newMode == "100755" && mode.path == "mode.sh")
    }

    @Test func noNewlineMarkerIsNotARow() throws {
        let diff = try DiffRows.parse(try Fixtures.text("edge/noeol.diff"))
        #expect(diff.rows == [
            DiffRow(kind: .context, oldLine: 1, newLine: 1, text: "a"),
            DiffRow(kind: .context, oldLine: 2, newLine: 2, text: "b"),
            DiffRow(kind: .deleted, oldLine: 3, newLine: nil, text: "c"),
            DiffRow(kind: .added, oldLine: nil, newLine: 3, text: "C"),
        ])
    }

    @Test func multiFileDiffSplitsPerFile() throws {
        let names = ["added", "binary", "deleted", "empty", "mode", "noeol", "renamed"]
        let text = try names.map { try Fixtures.text("edge/\($0).diff") }.joined()
        let files = try DiffRows.parseFiles(text)
        #expect(files.map(\.path) == ["added.txt", "img.bin", "gone.txt", "empty.txt", "mode.sh", "noeol.txt", "new_name.txt"])
        #expect(files.map(\.status) == [.added, .modified, .deleted, .added, .modified, .modified, .renamed])
        #expect(files.map(\.rows.count) == [5, 0, 3, 0, 0, 4, 5])
    }

    @Test func crlfQuotedPathsAndHunkRestarts() throws {
        let crlf = try DiffRows.parse("--- a/x\r\n+++ b/x\r\n@@ -1,2 +1,2 @@\r\n ctx\r\n-x\r\n+y\r\n")
        #expect(crlf.rows.map(\.text) == ["ctx", "x", "y"])
        #expect(crlf.path == "x")

        let quoted = try DiffRows.parse("diff --git \"a/caf\\303\\251 x.txt\" \"b/caf\\303\\251 x.txt\"\nnew file mode 100644\n")
        #expect(quoted.newPath == "café x.txt" && quoted.status == .added)

        // A -U3 diff: each hunk restarts both counters from its header.
        let hunks = try DiffRows.parse("@@ -1,2 +1,2 @@\n a\n-b\n+B\n@@ -10,1 +10,2 @@\n j\n+k\n")
        #expect(hunks.rows.map(\.oldLine) == [1, 2, nil, 10, nil])
        #expect(hunks.rows.map(\.newLine) == [1, nil, 2, 10, 11])
    }

    @Test func malformedInputIsAnError() {
        #expect(throws: DiffParseError.malformedHunkHeader("@@ -x +1 @@")) { try DiffRows.parse("@@ -x +1 @@\n") }
        #expect(throws: DiffParseError.truncatedHunk("@@ -1,3 +1,3 @@")) { try DiffRows.parse("@@ -1,3 +1,3 @@\n a\n") }
        #expect(throws: DiffParseError.truncatedHunk("@@ -1 +0,0 @@")) { try DiffRows.parse("@@ -1 +0,0 @@\n+a\n") }
    }
}
