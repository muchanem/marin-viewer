import Foundation
import ViewerCore

/// One line of a file card's body, top to bottom: a diff row, a gap bar
/// over hidden rows, or a review note opened below its row.
enum DiffLine: Hashable, Sendable {
    /// An index into the file's `FileDiff.rows`.
    case code(Int)
    case gap(DiffGap)
    case note(ReviewNote)

    var row: Int? {
        if case .code(let row) = self { return row }
        return nil
    }
}

/// What a card body draws: its lines, the note dot of each row that has
/// one, and the blame label of each row that starts a run. Built from
/// ViewerCore's segments, so the gaps, expanders and blame runs are the
/// ones `DemoParityTests` checks against the demo.
struct DiffCardRows: Hashable, Sendable {
    let lines: [DiffLine]
    /// Row index to the note whose dot the gutter shows.
    let dots: [Int: ReviewNote]
    /// Row index to the commit labelled on that row; empty with blame off.
    let blameLabels: [Int: BlameCommit]

    init(rows: [DiffRow], segments: [DiffSegment], path: String, notes: ReviewNotes,
         expandedNoteID: String?, blame: Blame?) {
        var lines: [DiffLine] = []
        var dots: [Int: ReviewNote] = [:]
        for segment in segments {
            switch segment {
            case .gap(let gap):
                lines.append(.gap(gap))
            case .rows(let range):
                for index in range {
                    lines.append(.code(index))
                    guard let note = notes.gutterNote(path: path, row: rows[index]) else { continue }
                    dots[index] = note
                    if note.id == expandedNoteID { lines.append(.note(note)) }
                }
            }
        }
        var labels: [Int: BlameCommit] = [:]
        if let blame {
            for index in blame.labeledRows(rows, segments: segments) {
                guard let line = rows[index].newLine, let sha = blame.sha(forNewLine: line) else { continue }
                labels[index] = blame.commits[sha] ?? BlameCommit(sha: sha, author: "", time: 0, summary: "")
            }
        }
        self.lines = lines
        self.dots = dots
        blameLabels = labels
    }

    /// The display line of a diff row, if the row is shown.
    func lineIndex(ofRow row: Int) -> Int? {
        lines.firstIndex { $0.row == row }
    }
}
