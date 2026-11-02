import Foundation
import Testing
@testable import Radiology

struct UnifiedDiffTests {
    @Test func parsesHunkHeadersAndSkipsEverythingElse() throws {
        let text = """
        diff --git a/x.kt b/x.kt
        index 3dbc46063..c2da84e31 100644
        --- a/x.kt
        +++ b/x.kt
        @@ -3,8 +2,0 @@ package inc.tk.os.engine
        -import java.io.InputStream
        @@ -20,0 +10 @@ import kotlinx.coroutines.launch
        +import kotlinx.coroutines.coroutineScope
        @@ -31,25 +20,21 @@ import kotlinx.serialization.json.int
        -/** old */
        +/** new */
        \\ No newline at end of file
        """
        let changes = try UnifiedDiffParser.parse(text)
        #expect(!changes.isBinary)
        #expect(changes.hunks == [
            DiffHunk(beforeStart: 3, beforeCount: 8, afterStart: 2, afterCount: 0),
            DiffHunk(beforeStart: 20, beforeCount: 0, afterStart: 10, afterCount: 1),
            DiffHunk(beforeStart: 31, beforeCount: 25, afterStart: 20, afterCount: 21),
        ])
        #expect(changes.changedLines(in: .after) == [10..<11, 20..<41])
        #expect(changes.changedLines(in: .before) == [3..<11, 31..<56])
        #expect(changes.changeAnchors(in: .after) == [3, 10, 20], "a pure deletion is anchored after the surviving line")
        #expect(changes.additions == 22)
        #expect(changes.deletions == 33)
    }

    @Test func pureAdditionsDeletionsBinaryAndCRLF() throws {
        let added = try UnifiedDiffParser.parse("--- /dev/null\n+++ b/new.rs\n@@ -0,0 +1,3 @@\n+a\n+b\n+c\n")
        #expect(added.hunks == [DiffHunk(beforeStart: 0, beforeCount: 0, afterStart: 1, afterCount: 3)])
        #expect(added.changedLines(in: .before).isEmpty)
        #expect(added.changeAnchors(in: .before) == [1])
        let deleted = try UnifiedDiffParser.parse("--- a/old.rs\n+++ /dev/null\n@@ -1,2 +0,0 @@\n-x\r\n-y\r\n")
        #expect(deleted.hunks == [DiffHunk(beforeStart: 1, beforeCount: 2, afterStart: 0, afterCount: 0)])
        #expect(deleted.changedLines(in: .before) == [1..<3])
        // CRLF-terminated hunk headers still parse; the trailing CR is not part of the header.
        let crlf = try UnifiedDiffParser.parse("@@ -4 +4 @@\r\n-é\r\n+🚀\r\n")
        #expect(crlf.hunks == [DiffHunk(beforeStart: 4, beforeCount: 1, afterStart: 4, afterCount: 1)])
        // A header right after a CRLF content line: "\r\n" is one Swift Character, so splitting must be byte-wise.
        let twoHunks = try UnifiedDiffParser.parse("@@ -2 +2 @@ line1\n-line2\r\n+line2 changed\r\n@@ -3,0 +4 @@ line3\n+line4\r\n")
        #expect(twoHunks.hunks.count == 2)
        #expect(twoHunks.changedLines(in: .after) == [2..<3, 4..<5])
        let binary = try UnifiedDiffParser.parse("diff --git a/i.png b/i.png\nBinary files a/i.png and b/i.png differ\n")
        #expect(binary.isBinary)
        #expect(binary.hunks.isEmpty)
        #expect(try UnifiedDiffParser.parse("").hunks.isEmpty)
        #expect(throws: BrowserError.self) { try UnifiedDiffParser.parse("@@ -x +1 @@\n") }
    }

    @Test func lineMapShiftsOutsideHunksAndLandsOnChangesInside() throws {
        // Consistent headers: each After start equals the Before start plus
        // the lines added and removed by the earlier hunks (-8, then +3).
        let changes = try UnifiedDiffParser.parse("@@ -3,8 +2,0 @@\n@@ -20,0 +10,3 @@\n@@ -31,2 +26,5 @@\n")
        let map = LineMap(changes)
        #expect(map.map(line: 1, from: .before) == 1)
        #expect(map.map(line: 2, from: .before) == 2)
        #expect(map.map(line: 3, from: .before) == 3, "a removed line maps to the line after the gap in After")
        #expect(map.map(line: 10, from: .before) == 3)
        #expect(map.map(line: 11, from: .before) == 3, "Before 11 is After 3 after eight removals")
        #expect(map.map(line: 20, from: .before) == 12, "Before 20 sits just before the three inserted lines")
        #expect(map.map(line: 21, from: .before) == 16)
        #expect(map.map(line: 31, from: .before) == 26)
        #expect(map.map(line: 33, from: .before) == 31)
        #expect(map.map(line: 40, from: .before) == 38)
        #expect(map.map(line: 3, from: .after) == 11, "After 3 comes after the removed block")
        #expect(map.map(line: 11, from: .after) == 21, "an added line maps to the line after the insertion point in Before")
        #expect(map.map(line: 25, from: .after) == 30)
        #expect(map.map(line: 26, from: .after) == 31)
        #expect(map.map(line: 29, from: .after) == 31)
        #expect(map.map(line: 100, from: .after) == 102)
    }

    @Test func rawRecordsCoverAddModifyDeleteRenameAndNumstat() throws {
        let raw = Data(":000000 100644 0000000000000000000000000000000000000000 1111111111111111111111111111111111111111 A\0a/new.kt\0:100644 100644 2222222222222222222222222222222222222222 3333333333333333333333333333333333333333 M\0src/é mod.rs\0:100644 000000 4444444444444444444444444444444444444444 0000000000000000000000000000000000000000 D\0gone.py\0:100644 100644 5555555555555555555555555555555555555555 6666666666666666666666666666666666666666 R099\0old/name.kt\0new/name.kt\0:100644 100644 7777777777777777777777777777777777777777 8888888888888888888888888888888888888888 M\0img.png\0".utf8)
        var changes = try FileChangeParser.parseRaw(raw)
        #expect(changes.map(\.path) == ["a/new.kt", "src/é mod.rs", "gone.py", "new/name.kt", "img.png"])
        #expect(changes[0].status == .added)
        #expect(changes[0].existsBefore == false && changes[0].existsAfter)
        #expect(changes[2].status == .deleted && !changes[2].existsAfter && changes[2].path(in: .before) == "gone.py")
        #expect(changes[3].status == .renamed(similarity: 99))
        #expect(changes[3].oldPath == "old/name.kt" && changes[3].path(in: .before) == "old/name.kt" && changes[3].path(in: .after) == "new/name.kt")
        #expect(changes[3].beforeBlob == "5555555555555555555555555555555555555555")
        let numstat = Data("206\t0\ta/new.kt\u{0}3\t2\tsrc/é mod.rs\u{0}0\t55\tgone.py\u{0}4\t1\t\u{0}old/name.kt\u{0}new/name.kt\u{0}-\t-\timg.png\u{0}".utf8)
        changes = FileChangeParser.applyNumstat(numstat, to: changes)
        #expect(changes[0].additions == 206 && changes[0].deletions == 0)
        #expect(changes[1].additions == 3 && changes[1].deletions == 2)
        #expect(changes[3].additions == 4 && changes[3].deletions == 1, "rename counts are matched to the new path")
        #expect(changes[4].isBinary)
        #expect(changes[4].status.title == "Modified")
        #expect(changes[3].status.title == "Renamed and modified")
        #expect(throws: BrowserError.self) { try FileChangeParser.parseRaw(Data("garbage\0".utf8)) }
    }

    @Test func locationsCarryRevisionsAndPositionKeys() {
        let plain = SourceLocation(path: "a.rs", byteOffset: 4)
        let after = plain.with(revision: .after)
        #expect(plain != after)
        #expect(plain.positionKey == "a.rs")
        #expect(after.positionKey == "after:a.rs")
        #expect(after.with(byteOffset: 9).revision == .after)
        #expect(!plain.sameDocument(as: after))
        #expect(after.sameDocument(as: after.with(byteOffset: 1)))
        #expect(ReviewRevision.before.other == .after)
    }
}
