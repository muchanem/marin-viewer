import AppKit
import ViewerCore

/// The code of one card body: a read-only TextKit 1 view whose paragraphs
/// are the card's lines. Code rows hold their text; gap bars and open notes
/// are empty paragraphs of their layout height, painted in
/// `drawBackground`. Selection, the find bar and copy are the native ones,
/// except that copy keeps only code rows, so a selection across a gap or a
/// note copies the code without blank lines, and deleted rows copy as the
/// text they had.
final class DiffCodeTextView: NSTextView {
    weak var model: DiffReaderModel?
    private(set) var content: DiffBodyContent?
    private(set) var layout: DiffCardLayout?
    /// UTF-16 start of each display line in the text storage.
    private var lineStarts: [Int] = []
    private var gapButtons: [(rect: NSRect, expander: GapExpander)] = []
    private var flashedLine: Int?
    private var flashGeneration = 0
    /// Width of the longest code row, padding included.
    private(set) var contentWidth: CGFloat = 0

    static func make() -> DiffCodeTextView {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        layoutManager.usesFontLeading = false
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = DiffReaderStyle.codeLeading
        layoutManager.addTextContainer(container)
        let view = DiffCodeTextView(frame: .zero, textContainer: container)
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = false
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.isAutomaticLinkDetectionEnabled = false
        view.textContainerInset = .zero
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.drawsBackground = true
        view.backgroundColor = DiffReaderStyle.pane
        view.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        view.setAccessibilityLabel("Read-only diff")
        return view
    }

    // MARK: - Content

    func apply(_ content: DiffBodyContent, layout: DiffCardLayout) {
        let rebuild = self.content?.identity != content.identity || self.layout != layout
        self.content = content
        self.layout = layout
        guard rebuild else { return }
        rebuildText()
        rebuildGapButtons()
        window?.invalidateCursorRects(for: self)
        setAccessibilityLabel("Diff of \(content.card.path)")
        needsDisplay = true
    }

    private func rebuildText() {
        guard let content, let layout else { return }
        let font = DiffReaderStyle.codeFont(size: content.fontSize)
        let natural = font.ascender - font.descender
        let raise = max(0, (layout.lineHeight - natural) / 2)
        let tab = font.maximumAdvancement.width * 4
        var styles: [CGFloat: NSParagraphStyle] = [:]
        func style(_ height: CGFloat) -> NSParagraphStyle {
            if let cached = styles[height] { return cached }
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = height
            paragraph.maximumLineHeight = height
            paragraph.tabStops = []
            paragraph.defaultTabInterval = tab
            styles[height] = paragraph
            return paragraph
        }
        let storage = NSMutableAttributedString()
        var starts: [Int] = []
        var widest = 0
        storage.beginEditing()
        for (index, line) in content.rows.lines.enumerated() {
            starts.append(storage.length)
            var text = ""
            var spans: [LineHighlight] = []
            if case .code(let row) = line {
                text = content.diffRows[row].text
                spans = content.file.highlights(for: content.diffRows[row])
                widest = max(widest, text.utf16.count)
            }
            let piece = NSMutableAttributedString(string: text + "\n", attributes: [
                .font: font, .foregroundColor: DiffReaderStyle.ink,
                .paragraphStyle: style(layout.heights[index]), .baselineOffset: raise,
            ])
            let length = (text as NSString).length
            for span in spans where span.range.location < length {
                let range = NSRange(location: span.range.location, length: min(span.range.length, length - span.range.location))
                piece.addAttribute(.foregroundColor, value: Theme.SyntaxColors.color(for: span.capture), range: range)
            }
            storage.append(piece)
        }
        storage.endEditing()
        lineStarts = starts
        textStorage?.setAttributedString(storage)
        let advance = font.maximumAdvancement.width
        contentWidth = CGFloat(widest) * advance + DiffReaderStyle.codeLeading + DiffReaderStyle.codeTrailing
        if let layout = self.layout {
            contentWidth = max(contentWidth, layout.noteWidth + DiffReaderStyle.codeLeading + DiffReaderStyle.noteOuterTrailing)
        }
    }

    // MARK: - Lines and positions

    /// The display line holding a UTF-16 offset.
    func line(atCharacter index: Int) -> Int? {
        guard !lineStarts.isEmpty else { return nil }
        var low = 0, high = lineStarts.count
        while low < high {
            let middle = (low + high) / 2
            if lineStarts[middle] <= index { low = middle + 1 } else { high = middle }
        }
        return max(0, low - 1)
    }

    /// The diff row and UTF-16 column under a point, for code lines only.
    private func position(at point: NSPoint) -> (row: Int, line: Int, column: Int)? {
        guard let content, let layout, let lineIndex = layout.line(atY: point.y),
              case .code(let row) = content.rows.lines[lineIndex] else { return nil }
        let index = characterIndexForInsertion(at: point)
        let column = max(0, min(index - lineStarts[lineIndex], (content.diffRows[row].text as NSString).length))
        return (row, lineIndex, column)
    }

    /// The identifier at a point: letters, digits and underscores around the
    /// character under it.
    func identifier(at point: NSPoint) -> (word: String, row: Int)? {
        guard let content, let position = position(at: point) else { return nil }
        let text = content.diffRows[position.row].text as NSString
        guard let word = Self.identifier(in: text, at: position.column) else { return nil }
        return (word, position.row)
    }

    static func identifier(in text: NSString, at column: Int) -> String? {
        func isWord(_ index: Int) -> Bool {
            guard index >= 0, index < text.length, let scalar = UnicodeScalar(text.character(at: index)) else { return false }
            return scalar == "_" || CharacterSet.alphanumerics.contains(scalar)
        }
        var lower = column, upper = column
        if !isWord(column), isWord(column - 1) { lower -= 1; upper -= 1 }
        guard isWord(lower) else { return nil }
        while isWord(lower - 1) { lower -= 1 }
        while isWord(upper + 1) { upper += 1 }
        let word = text.substring(with: NSRange(location: lower, length: upper - lower + 1))
        return word.first?.isNumber == true ? nil : word
    }

    /// Head lines covered by the selection, or nil when it holds only
    /// deleted rows or no code at all.
    func selectedHeadLines() -> ClosedRange<Int>? {
        guard let content else { return nil }
        let lines = selectedDisplayLines().compactMap { content.rows.lines[$0].row.flatMap(content.newLine(ofRow:)) }
        guard let first = lines.min(), let last = lines.max() else { return nil }
        return first...last
    }

    var hasCodeSelection: Bool {
        guard let content else { return false }
        return selectedRange().length > 0
            && selectedDisplayLines().contains { content.rows.lines[$0].row != nil }
    }

    private func selectedDisplayLines() -> [Int] {
        var lines: [Int] = []
        for value in selectedRanges {
            let range = value.rangeValue
            guard range.length > 0, let first = line(atCharacter: range.location),
                  let last = line(atCharacter: NSMaxRange(range) - 1) else { continue }
            lines.append(contentsOf: first...last)
        }
        return lines
    }

    // MARK: - Copy

    /// The selected text of code rows only, one row per line.
    func selectedCodeText() -> String {
        guard let content else { return "" }
        var pieces: [String] = []
        var endsWithNewline = false
        for value in selectedRanges {
            let range = value.rangeValue
            guard range.length > 0, let first = line(atCharacter: range.location),
                  let last = line(atCharacter: NSMaxRange(range) - 1) else { continue }
            for index in first...last {
                guard case .code(let row) = content.rows.lines[index] else { continue }
                let text = content.diffRows[row].text as NSString
                let start = lineStarts[index]
                let lower = max(range.location, start) - start
                let upper = min(NSMaxRange(range), start + text.length) - start
                pieces.append(upper > lower ? text.substring(with: NSRange(location: lower, length: upper - lower)) : "")
                endsWithNewline = NSMaxRange(range) > start + text.length
            }
        }
        return pieces.joined(separator: "\n") + (endsWithNewline && !pieces.isEmpty ? "\n" : "")
    }

    override func copy(_ sender: Any?) {
        let text = selectedCodeText()
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let text = selectedCodeText()
        guard !text.isEmpty else { return false }
        pboard.clearContents()
        return pboard.setString(text, forType: .string)
    }

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] { [.string] }

    // MARK: - Drawing

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let content, let layout else { return }
        let width = max(bounds.width, visibleRect.maxX)
        for index in layout.lines(in: rect) {
            let box = layout.rect(ofLine: index, width: width)
            switch content.rows.lines[index] {
            case .code(let row):
                switch content.diffRows[row].kind {
                case .added: DiffReaderStyle.added.setFill(); box.fill()
                case .deleted: DiffReaderStyle.deleted.setFill(); box.fill()
                case .context: break
                }
            case .gap(let gap):
                Self.drawGapBar(in: box)
                drawGapText(gap, in: box)
            case .note(let note):
                drawNote(note, in: box, layout: layout)
            }
            if index == flashedLine {
                DiffReaderStyle.flash.withAlphaComponent(0.85).setFill()
                box.fill()
                DiffReaderStyle.note.setFill()
                NSRect(x: box.minX, y: box.minY, width: 4, height: box.height).fill()
            }
        }
    }

    static func drawGapBar(in box: NSRect) {
        DiffReaderStyle.gapFill.setFill()
        box.fill()
        DiffReaderStyle.gapRule.setFill()
        NSRect(x: box.minX, y: box.minY, width: box.width, height: 1).fill()
        NSRect(x: box.minX, y: box.maxY - 1, width: box.width, height: 1).fill()
    }

    static let gapFont = NSFont.systemFont(ofSize: DiffReaderStyle.interfaceFontSize)

    private func drawGapText(_ gap: DiffGap, in box: NSRect) {
        let label = NSAttributedString(string: gap.label, attributes: [.font: Self.gapFont, .foregroundColor: DiffReaderStyle.muted])
        let size = label.size()
        label.draw(at: NSPoint(x: DiffReaderStyle.codeLeading, y: box.midY - size.height / 2))
        for button in gapButtons where button.rect.minY >= box.minY && button.rect.maxY <= box.maxY {
            NSAttributedString(string: button.expander.title, attributes: [.font: Self.gapFont, .foregroundColor: DiffReaderStyle.accent])
                .draw(at: button.rect.origin)
        }
    }

    /// Where each gap's expanders are drawn, measured once per content.
    private func rebuildGapButtons() {
        gapButtons = []
        guard let content, let layout else { return }
        for (index, line) in content.rows.lines.enumerated() {
            guard case .gap(let gap) = line else { continue }
            let box = layout.rect(ofLine: index, width: 0)
            var x = DiffReaderStyle.codeLeading
                + NSAttributedString(string: gap.label, attributes: [.font: Self.gapFont]).size().width
            for expander in gap.expanders {
                x += DiffReaderStyle.gapButtonSpacing
                let size = NSAttributedString(string: expander.title, attributes: [.font: Self.gapFont]).size()
                gapButtons.append((NSRect(x: x, y: box.midY - size.height / 2, width: size.width, height: size.height), expander))
                x += size.width
            }
        }
    }

    private func drawNote(_ note: ReviewNote, in box: NSRect, layout: DiffCardLayout) {
        let card = NSRect(x: DiffReaderStyle.codeLeading, y: box.minY + DiffReaderStyle.noteOuterTop,
                          width: layout.noteWidth,
                          height: box.height - DiffReaderStyle.noteOuterTop - DiffReaderStyle.noteOuterBottom)
        let path = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: DiffReaderStyle.noteCornerRadius, yRadius: DiffReaderStyle.noteCornerRadius)
        DiffReaderStyle.noteSoft.setFill()
        path.fill()
        DiffReaderStyle.noteRule.setStroke()
        path.lineWidth = 1
        path.stroke()
        let text = card.insetBy(dx: DiffReaderStyle.notePaddingHorizontal, dy: DiffReaderStyle.notePaddingVertical + 1)
        DiffNoteText.attributed(note).draw(with: text, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }

    /// Washes a line in the demo's amber for a moment after Go to Line.
    func flash(line: Int) {
        flashedLine = line
        flashGeneration += 1
        let generation = flashGeneration
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + DiffReaderStyle.flashDuration) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            self.flashedLine = nil
            self.needsDisplay = true
        }
    }

    // MARK: - Mouse

    override func resetCursorRects() {
        super.resetCursorRects()
        for button in gapButtons { addCursorRect(button.rect, cursor: .pointingHand) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let content, let button = gapButtons.first(where: { $0.rect.insetBy(dx: -3, dy: -3).contains(point) }) {
            model?.expand(button.expander, in: content.card)
            return
        }
        if event.modifierFlags.contains(.command), let request = definitionRequest(at: point), request.destination != nil {
            model?.goToDefinition(request)
            return
        }
        super.mouseDown(with: event)
    }

    private func definitionRequest(at point: NSPoint) -> DiffDefinitionRequest? {
        guard let content, let model, let hit = identifier(at: point) else { return nil }
        let origin = DiffCodeTarget(path: content.card.path, line: content.newLine(ofRow: hit.row))
        return DiffDefinitionRequest(symbol: hit.word, origin: origin, destination: model.definition(of: hit.word, at: origin))
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let content, let model else { return super.menu(for: event) }
        let point = convert(event.locationInWindow, from: nil)
        let menu = NSMenu()
        let hit = identifier(at: point)
        let request = definitionRequest(at: point)
        if let request, let destination = request.destination {
            menu.addItem(DiffMenuAction.item("Go to Definition of \(request.symbol)") { model.goToDefinition(request) })
            menu.addItem(DiffMenuAction.item("Open Definition in New Window") { model.openInNewWindow(destination) })
            menu.addItem(.separator())
        }
        let path = content.card.path
        if hasCodeSelection {
            let lines = selectedHeadLines()
            menu.addItem(DiffMenuAction.item("Ask About Selection", key: ">") { model.ask(model.selectionChip(path: path, lines: lines)) })
        }
        if let hit {
            let origin = DiffCodeTarget(path: path, line: content.newLine(ofRow: hit.row))
            menu.addItem(DiffMenuAction.item("Ask About \(hit.word)", key: hasCodeSelection ? "" : ">") {
                model.ask(model.symbolChip(hit.word, at: origin))
            })
        }
        if let position = position(at: point), let line = content.newLine(ofRow: position.row) {
            menu.addItem(DiffMenuAction.item("Ask About Line \(line)") { model.ask(model.lineChip(path: path, line: line)) })
        }
        if menu.items.last?.isSeparatorItem == false { menu.addItem(.separator()) }
        menu.addItem(DiffMenuAction.item(model.showBlame ? "Hide Blame" : "Show Blame") { model.showBlame.toggle() })
        menu.addItem(.separator())
        let copy = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        copy.target = self
        copy.isEnabled = selectedRange().length > 0
        menu.addItem(copy)
        return menu
    }

    // MARK: - Keyboard

    /// ⌘> asks about the selection, else the identifier at the caret, else
    /// the caret's line.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, Self.isAskShortcut(event) {
            askFromKeyboard()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    static func isAskShortcut(_ event: NSEvent) -> Bool {
        event.type == .keyDown && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
            && event.charactersIgnoringModifiers == ">"
            || (event.type == .keyDown && event.modifierFlags.contains([.command, .shift]) && event.charactersIgnoringModifiers == ".")
    }

    func askFromKeyboard() {
        guard let content, let model else { return }
        let path = content.card.path
        if hasCodeSelection {
            model.ask(model.selectionChip(path: path, lines: selectedHeadLines()))
            return
        }
        let caret = selectedRange().location
        guard let lineIndex = line(atCharacter: caret), case .code(let row) = content.rows.lines[lineIndex] else { return }
        let text = content.diffRows[row].text as NSString
        let column = caret - lineStarts[lineIndex]
        let origin = DiffCodeTarget(path: path, line: content.newLine(ofRow: row))
        if let word = Self.identifier(in: text, at: column) {
            model.ask(model.symbolChip(word, at: origin))
        } else if let line = origin.line {
            model.ask(model.lineChip(path: path, line: line))
        }
    }
}

/// A menu item that runs a closure.
final class DiffMenuAction: NSObject {
    private let run: () -> Void

    private init(_ run: @escaping () -> Void) { self.run = run }

    @objc private func runAction() { run() }

    static func item(_ title: String, key: String = "", run: @escaping () -> Void) -> NSMenuItem {
        let action = DiffMenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(runAction), keyEquivalent: key)
        item.target = action
        item.representedObject = action
        return item
    }
}
