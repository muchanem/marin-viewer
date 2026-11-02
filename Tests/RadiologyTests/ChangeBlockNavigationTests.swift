import Foundation
import Testing
@testable import Radiology

struct ChangeBlockNavigationTests {
    @Test func insideBlocksSkipsCurrentAndGapsChooseClosestWithoutWrap() throws {
        var buffer = try SourceBuffer(path: "a.rs", data: Data((1...30).map { "line\($0)" }.joined(separator: "\n").utf8))
        buffer.revision = .after
        let changes = FileLineChanges(hunks: [
            .init(beforeStart: 3, beforeCount: 3, afterStart: 3, afterCount: 3),
            .init(beforeStart: 12, beforeCount: 2, afterStart: 12, afterCount: 2),
            .init(beforeStart: 23, beforeCount: 1, afterStart: 23, afterCount: 1)], isBinary: false)
        func nav(_ line: Int) -> ChangeBlockNavigation { .init(changes: changes, buffer: buffer, caret: buffer.byteOffset(line: line) + 1) }
        #expect(nav(4).previousByte == nil && nav(4).nextByte == buffer.byteOffset(line: 12))
        #expect(nav(13).previousByte == buffer.byteOffset(line: 3) && nav(13).nextByte == buffer.byteOffset(line: 23))
        #expect(nav(9).previousByte == buffer.byteOffset(line: 3) && nav(9).nextByte == buffer.byteOffset(line: 12))
        #expect(nav(1).previousByte == nil && nav(1).nextByte == buffer.byteOffset(line: 3))
        #expect(nav(24).nextByte == nil && nav(24).previousByte == buffer.byteOffset(line: 23))
        #expect(ChangeBlockNavigation(changes: .none, buffer: buffer, caret: 0).nextByte == nil)
        #expect(ChangeBlockNavigation(changes: .binary, buffer: buffer, caret: 0).previousByte == nil)
    }

    @Test func EOFOnUnterminatedChangedLineBelongsToCurrentBlock() throws {
        var buffer = try SourceBuffer(path: "a.rs", data: Data("changed".utf8))
        buffer.revision = .after
        let changes = FileLineChanges(hunks: [.init(beforeStart: 1, beforeCount: 1, afterStart: 1, afterCount: 1)], isBinary: false)
        let eof = ChangeBlockNavigation(changes: changes, buffer: buffer, caret: buffer.data.count)
        #expect(eof.previousByte == nil && eof.nextByte == nil)
        var terminated = try SourceBuffer(path: "a.rs", data: Data("changed\n".utf8))
        terminated.revision = .after
        #expect(ChangeBlockNavigation(changes: changes, buffer: terminated, caret: terminated.data.count).previousByte == 0,
                "a trailing empty line is outside the changed block")
    }

    @Test func emptySideAtEOFWithoutFinalNewlineRemainsReachableWithoutHighlights() throws {
        var after = try SourceBuffer(path: "a.rs", data: Data("one\ntwo".utf8))
        after.revision = .after
        let deleted = FileLineChanges(hunks: [.init(beforeStart: 3, beforeCount: 2, afterStart: 2, afterCount: 0)], isBinary: false)
        #expect(deleted.changedLines(in: .after).isEmpty)
        let next = ChangeBlockNavigation(changes: deleted, buffer: after, caret: 0)
        #expect(next.nextByte == after.data.count)
        let end = ChangeBlockNavigation(changes: deleted, buffer: after, caret: after.data.count)
        #expect(end.previousByte == nil && end.nextByte == nil)
        after.revision = .before
        let inserted = FileLineChanges(hunks: [.init(beforeStart: 2, beforeCount: 0, afterStart: 3, afterCount: 2)], isBinary: false)
        #expect(ChangeBlockNavigation(changes: inserted, buffer: after, caret: 0).nextByte == after.data.count)
        #expect(inserted.changedLines(in: .before).isEmpty)
    }
}
