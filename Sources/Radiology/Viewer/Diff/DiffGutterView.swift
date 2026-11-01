import AppKit
import ViewerCore

/// The card's left columns, fixed while the code scrolls sideways: blame
/// (when shown), old and new line numbers, and a marker column with `+`,
/// `−` or a review-note dot. Drawn per visible line from `DiffCardLayout`.
final class DiffGutterView: NSView, NSViewToolTipOwner {
    weak var model: DiffReaderModel?
    private var content: DiffBodyContent?
    private var layout: DiffCardLayout?
    /// Baseline of code text inside a code row, measured from the text view.
    var codeBaseline: CGFloat = 14

    override var isFlipped: Bool { true }

    func apply(_ content: DiffBodyContent, layout: DiffCardLayout) {
        let changed = self.content?.identity != content.identity || self.layout != layout
        self.content = content
        self.layout = layout
        if changed {
            rebuildToolTips()
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    private var blameWidth: CGFloat { content?.showBlame == true ? DiffReaderStyle.blameColumnWidth : 0 }
    private var markerX: CGFloat { blameWidth + 2 * DiffReaderStyle.numberColumnWidth }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        DiffReaderStyle.pane.setFill()
        dirtyRect.intersection(bounds).fill()
        guard let content, let layout else { return }
        let numberFont = DiffReaderStyle.numberFont(size: content.fontSize)
        for index in layout.lines(in: dirtyRect) {
            let box = layout.rect(ofLine: index, width: bounds.width)
            switch content.rows.lines[index] {
            case .gap:
                DiffCodeTextView.drawGapBar(in: box)
            case .note:
                continue
            case .code(let row):
                drawCode(row: row, in: box, content: content, numberFont: numberFont)
            }
        }
    }

    private func drawCode(row: Int, in box: NSRect, content: DiffBodyContent, numberFont: NSFont) {
        let diffRow = content.diffRows[row]
        let numbers = NSRect(x: blameWidth, y: box.minY, width: 2 * DiffReaderStyle.numberColumnWidth, height: box.height)
        var numberColor = DiffReaderStyle.lineNumber
        switch diffRow.kind {
        case .added:
            DiffReaderStyle.added.setFill(); box.fill()
            DiffReaderStyle.addedStrong.setFill(); numbers.fill()
            numberColor = DiffReaderStyle.addedNumber
        case .deleted:
            DiffReaderStyle.deleted.setFill(); box.fill()
            DiffReaderStyle.deletedStrong.setFill(); numbers.fill()
            numberColor = DiffReaderStyle.deletedNumber
        case .context:
            break
        }
        let baseline = box.minY + codeBaseline
        let attributes: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: numberColor]
        for (column, number) in [diffRow.oldLine, diffRow.newLine].enumerated() {
            guard let number else { continue }
            let text = NSAttributedString(string: "\(number)", attributes: attributes)
            let right = blameWidth + CGFloat(column + 1) * DiffReaderStyle.numberColumnWidth - DiffReaderStyle.numberTrailingPadding
            text.draw(at: NSPoint(x: right - text.size().width, y: baseline - numberFont.ascender))
        }
        if content.showBlame {
            DiffReaderStyle.rule.setFill()
            NSRect(x: blameWidth - 1, y: box.minY, width: 1, height: box.height).fill()
            if let label = content.blameLabels[row] { drawBlame(label, baseline: baseline, fontSize: content.fontSize) }
        }
        if let note = content.rows.dots[row] {
            let diameter = DiffReaderStyle.noteDotDiameter
            let dot = NSRect(x: markerX + (DiffReaderStyle.markerColumnWidth - diameter) / 2,
                             y: box.midY - diameter / 2, width: diameter, height: diameter)
            Self.color(of: note).setFill()
            NSBezierPath(ovalIn: dot).fill()
        } else if diffRow.kind != .context {
            let marker = NSAttributedString(string: diffRow.kind == .added ? "+" : "−", attributes: [
                .font: DiffReaderStyle.codeFont(size: content.fontSize), .foregroundColor: DiffReaderStyle.muted,
            ])
            let size = marker.size()
            let font = DiffReaderStyle.codeFont(size: content.fontSize)
            marker.draw(at: NSPoint(x: markerX + (DiffReaderStyle.markerColumnWidth - size.width) / 2, y: baseline - font.ascender))
        }
    }

    /// "97704d9 Russell · 61d": the SHA in the accent's monospaced face, the
    /// rest in small secondary text, truncated to the column.
    private func drawBlame(_ label: String, baseline: CGFloat, fontSize: CGFloat) {
        let parts = label.split(separator: " ", maxSplits: 1).map(String.init)
        let small = NSFont.systemFont(ofSize: fontSize - 1.5)
        let mono = NSFont.monospacedSystemFont(ofSize: fontSize - 1.5, weight: .regular)
        let text = NSMutableAttributedString(string: parts[0], attributes: [.font: mono, .foregroundColor: DiffReaderStyle.accent])
        if parts.count > 1 {
            text.append(NSAttributedString(string: " " + parts[1], attributes: [.font: small, .foregroundColor: DiffReaderStyle.muted]))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        let padding = DiffReaderStyle.blameHorizontalPadding
        let rect = NSRect(x: padding, y: baseline - small.ascender, width: blameWidth - 2 * padding, height: small.ascender - small.descender + 2)
        text.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    static func color(of note: ReviewNote) -> NSColor {
        switch note.marker {
        case .mine: DiffReaderStyle.accent
        case .resolved: DiffReaderStyle.resolvedDot
        case .draft, nil: DiffReaderStyle.note
        }
    }

    // MARK: - Clicks and tooltips

    private func markerRect(ofLine index: Int, layout: DiffCardLayout) -> NSRect {
        NSRect(x: markerX - 4, y: layout.tops[index], width: DiffReaderStyle.markerColumnWidth + 8, height: layout.heights[index])
    }

    private func note(at point: NSPoint) -> ReviewNote? {
        guard let content, let layout, let index = layout.line(atY: point.y),
              case .code(let row) = content.rows.lines[index], let note = content.rows.dots[row],
              markerRect(ofLine: index, layout: layout).contains(point) else { return nil }
        return note
    }

    override func mouseDown(with event: NSEvent) {
        if let note = note(at: convert(event.locationInWindow, from: nil)) {
            model?.toggleNote(note.id)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func resetCursorRects() {
        guard let content, let layout else { return }
        for (index, line) in content.rows.lines.enumerated() {
            if case .code(let row) = line, content.rows.dots[row] != nil {
                addCursorRect(markerRect(ofLine: index, layout: layout), cursor: .pointingHand)
            }
        }
    }

    private func rebuildToolTips() {
        removeAllToolTips()
        guard let content, let layout else { return }
        for (index, line) in content.rows.lines.enumerated() {
            guard case .code(let row) = line else { continue }
            if content.rows.dots[row] != nil { addToolTip(markerRect(ofLine: index, layout: layout), owner: self, userData: nil) }
            if content.showBlame, content.blameTooltips[row] != nil {
                addToolTip(NSRect(x: 0, y: layout.tops[index], width: blameWidth, height: layout.heights[index]), owner: self, userData: nil)
            }
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let content, let layout, let index = layout.line(atY: point.y), case .code(let row) = content.rows.lines[index] else { return "" }
        if point.x < blameWidth { return content.blameTooltips[row] ?? "" }
        return content.rows.dots[row]?.l1.replacingOccurrences(of: "`", with: "") ?? ""
    }
}
