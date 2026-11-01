import AppKit
import ViewerCore

/// Vertical positions of a card body's lines. Code rows have one fixed
/// height, gap bars another, and an open note the height of its wrapped
/// text, so the text view's paragraphs, the gutter and scrolling all use
/// these numbers and never ask TextKit where a line went.
struct DiffCardLayout: Equatable {
    let tops: [CGFloat]
    let heights: [CGFloat]
    let lineHeight: CGFloat
    /// Width the note cards were wrapped to.
    let noteWidth: CGFloat

    var totalHeight: CGFloat { (tops.last ?? 0) + (heights.last ?? 0) }

    init(lines: [DiffLine], fontSize: CGFloat, availableWidth: CGFloat, gutterWidth: CGFloat) {
        lineHeight = DiffReaderStyle.lineHeight(fontSize: fontSize)
        noteWidth = Self.noteWidth(availableWidth: availableWidth, gutterWidth: gutterWidth)
        var tops: [CGFloat] = []
        var heights: [CGFloat] = []
        var y: CGFloat = 0
        for line in lines {
            let height: CGFloat
            switch line {
            case .code: height = lineHeight
            case .gap: height = DiffReaderStyle.gapHeight
            case .note(let note):
                height = DiffReaderStyle.noteOuterTop + DiffNoteText.cardHeight(note, width: noteWidth)
                    + DiffReaderStyle.noteOuterBottom
            }
            tops.append(y)
            heights.append(height)
            y += height
        }
        self.tops = tops
        self.heights = heights
    }

    /// The note card's width in a body `availableWidth` wide, gutter included.
    static func noteWidth(availableWidth: CGFloat, gutterWidth: CGFloat) -> CGFloat {
        let room = availableWidth - gutterWidth - DiffReaderStyle.noteOuterTrailing
        return max(240, min(DiffReaderStyle.noteMaxWidth, room))
    }

    /// The line at a y offset, clamped to the body.
    func line(atY y: CGFloat) -> Int? {
        guard !tops.isEmpty else { return nil }
        var low = 0, high = tops.count
        while low < high {
            let middle = (low + high) / 2
            if tops[middle] <= y { low = middle + 1 } else { high = middle }
        }
        return max(0, low - 1)
    }

    func rect(ofLine index: Int, width: CGFloat) -> NSRect {
        NSRect(x: 0, y: tops[index], width: width, height: heights[index])
    }

    /// Lines whose boxes cross `rect`'s vertical span.
    func lines(in rect: NSRect) -> Range<Int> {
        guard let first = line(atY: rect.minY), let last = line(atY: rect.maxY) else { return 0..<0 }
        return first..<(last + 1)
    }
}

/// The text of an inline review note, as the demo's `.inline-note`: a quiet
/// "who · severity · status" line, then the note's first layer with
/// backticked code set in the monospaced face.
enum DiffNoteText {
    static var whoFont: NSFont { .systemFont(ofSize: 11) }
    static var bodyFont: NSFont { .systemFont(ofSize: 12) }

    static func attributed(_ note: ReviewNote) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = DiffReaderStyle.noteLineSpacing
        let text = NSMutableAttributedString(
            string: "\(note.who) · \(note.severity.rawValue) · \(note.status.rawValue)\n",
            attributes: [.font: whoFont, .foregroundColor: DiffReaderStyle.muted, .paragraphStyle: paragraph])
        text.append(inlineCode(note.l1, font: bodyFont, color: DiffReaderStyle.ink, paragraph: paragraph))
        return text
    }

    /// Backticked spans in the monospaced face on the demo's soft fill.
    static func inlineCode(_ string: String, font: NSFont, color: NSColor, paragraph: NSParagraphStyle) -> NSAttributedString {
        let output = NSMutableAttributedString()
        let code = NSFont.monospacedSystemFont(ofSize: font.pointSize - 0.5, weight: .regular)
        for (index, part) in string.components(separatedBy: "`").enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if index % 2 == 1 {
                attributes[.font] = code
                attributes[.backgroundColor] = DiffReaderStyle.soft
            }
            output.append(NSAttributedString(string: part, attributes: attributes))
        }
        return output
    }

    static func textRect(_ note: ReviewNote, width: CGFloat) -> NSRect {
        attributed(note).boundingRect(
            with: NSSize(width: width - 2 * DiffReaderStyle.notePaddingHorizontal, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    static func cardHeight(_ note: ReviewNote, width: CGFloat) -> CGFloat {
        ceil(textRect(note, width: width).height) + 2 * DiffReaderStyle.notePaddingVertical + 2
    }
}
