import AppKit
import ViewerCore

/// Everything one card body draws, handed from SwiftUI to the AppKit views.
struct DiffBodyContent {
    let card: DiffReaderModel.Card
    let file: PRFileReview
    let rows: DiffCardRows
    let fontSize: CGFloat
    let showBlame: Bool
    /// Row index to "97704d9 Russell · 61d".
    let blameLabels: [Int: String]
    /// Row index to the commit summary tooltip.
    let blameTooltips: [Int: String]

    /// What, besides the width, decides the body's text and layout.
    struct Identity: Hashable {
        let cardID: String
        let rows: DiffCardRows
        let fontSize: CGFloat
        let showBlame: Bool
        let blameLabels: [Int: String]
    }

    var identity: Identity {
        Identity(cardID: card.id, rows: rows, fontSize: fontSize, showBlame: showBlame, blameLabels: blameLabels)
    }

    var diffRows: [DiffRow] { file.diff.rows }
    var gutterWidth: CGFloat { DiffReaderStyle.gutterWidth(blame: showBlame) }

    func layout(width: CGFloat) -> DiffCardLayout {
        DiffCardLayout(lines: rows.lines, fontSize: fontSize, availableWidth: width, gutterWidth: gutterWidth)
    }

    @MainActor
    init(model: DiffReaderModel, card: DiffReaderModel.Card, file: PRFileReview) {
        self.card = card
        self.file = file
        rows = model.rows(for: card)
        fontSize = model.fontSize
        showBlame = model.showBlame
        var labels: [Int: String] = [:]
        var tooltips: [Int: String] = [:]
        for (row, commit) in rows.blameLabels {
            labels[row] = model.blameLabel(commit)
            tooltips[row] = commit.tooltip
        }
        blameLabels = labels
        blameTooltips = tooltips
    }

    /// The head line of a row, or nil for a deleted row.
    func newLine(ofRow row: Int) -> Int? { diffRows[row].newLine }
}
