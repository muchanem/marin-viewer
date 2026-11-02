import Foundation

/// Per-hunk destinations in one exact revision. Empty sides are insertion
/// points, including EOF, and never become invented changed-line highlights.
struct ChangeBlockNavigation: Equatable {
    let previousByte: Int?
    let nextByte: Int?

    init(changes: FileLineChanges, buffer: SourceBuffer, caret: Int) {
        guard !changes.isBinary else { previousByte = nil; nextByte = nil; return }
        let revision = buffer.revision ?? .after
        func byte(_ line: Int) -> Int {
            line > buffer.lineCount ? buffer.data.count : buffer.byteOffset(line: max(1, line))
        }
        var blocks: [Range<Int>] = []
        for hunk in changes.hunks {
            let range = revision == .after ? hunk.addedLines : hunk.removedLines
            let start = range.isEmpty ? max(1, (revision == .after ? hunk.afterStart : hunk.beforeStart) + 1) : range.lowerBound
            let target = byte(start)
            let block = target..<(range.isEmpty ? target : max(target, byte(range.upperBound)))
            // Two empty-side hunks can clamp to the same EOF destination.
            if blocks.last?.lowerBound != target { blocks.append(block) }
        }
        let inside = blocks.firstIndex {
            $0.contains(caret) || ($0.isEmpty && $0.lowerBound == caret)
                || (!$0.isEmpty && $0.upperBound == buffer.data.count && caret == buffer.data.count
                    && buffer.data.last != UInt8(ascii: "\n"))
        }
        if let inside {
            previousByte = inside > 0 ? blocks[inside - 1].lowerBound : nil
            nextByte = inside + 1 < blocks.count ? blocks[inside + 1].lowerBound : nil
        } else {
            previousByte = blocks.last { $0.lowerBound < caret }?.lowerBound
            nextByte = blocks.first { $0.lowerBound > caret }?.lowerBound
        }
    }
}
