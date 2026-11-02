import Foundation

/// Matched PR hunks for one loaded document, independent of painted line washes.
struct ReviewFoldInput: Equatable {
    let reviewID: String
    let path: String
    let revision: ReviewRevision
    let sourceIdentity: SourceContentIdentity
    let changes: FileLineChanges

    func foldsToExpand(in syntax: SyntaxSnapshot, buffer: SourceBuffer) -> Set<String> {
        guard !changes.isBinary else { return [] }
        func byte(_ line: Int) -> Int {
            line > buffer.lineCount ? buffer.data.count : buffer.byteOffset(line: max(1, line))
        }
        var selected = Set<String>()
        for hunk in changes.hunks {
            let lines = revision == .after ? hunk.addedLines : hunk.removedLines
            let point = byte(max(1, (revision == .after ? hunk.afterStart : hunk.beforeStart) + 1))
            let range = byte(lines.lowerBound)..<byte(lines.upperBound)
            for fold in syntax.folds {
                let overlaps: Bool
                if lines.isEmpty {
                    // A boundary after a closed braced body is outside it, not
                    // evidence that an unrelated preceding function changed.
                    let closedBrace = fold.byteRange.upperBound == buffer.data.count
                        && buffer.data.last == UInt8(ascii: "}")
                    let atOpenEOF = point == buffer.data.count && buffer.data.last != UInt8(ascii: "\n")
                        && fold.byteRange.upperBound == point && !closedBrace
                    overlaps = fold.byteRange.contains(point) || atOpenEOF
                } else {
                    overlaps = fold.byteRange.overlaps(range)
                }
                if overlaps { selected.insert(fold.id); continue }
                // Function/closure header edits own only their own body fold,
                // not every sibling closure contained by the enclosing function.
                if !lines.isEmpty, fold.kind == "function",
                   let owner = syntax.scopes.filter({
                       ($0.kind == "function" || $0.kind == "closure")
                           && $0.byteRange.lowerBound <= fold.byteRange.lowerBound
                           && $0.byteRange.upperBound == fold.byteRange.upperBound
                   }).min(by: { $0.byteRange.count < $1.byteRange.count }) {
                    let header = syntax.foldHeaderOwnership.first { $0.declarationByteRange == owner.byteRange }
                    if (header?.annotatedByteRange ?? owner.byteRange).overlaps(range) { selected.insert(fold.id) }
                }
            }
        }
        let targets = syntax.folds.filter { selected.contains($0.id) }
        for ancestor in syntax.folds where targets.contains(where: {
            ancestor.byteRange.lowerBound <= $0.byteRange.lowerBound && $0.byteRange.upperBound <= ancestor.byteRange.upperBound
        }) { selected.insert(ancestor.id) }
        return selected
    }
}
