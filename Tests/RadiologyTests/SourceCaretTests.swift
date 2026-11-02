import AppKit
import Testing
@testable import Radiology

/// The read-only reader's insertion caret: geometry comes from TextKit's laid
/// out glyphs, and it shows only for an empty selection in the focused reader.
@MainActor
struct SourceCaretTests {
    static func reader(_ text: String) -> ReaderTextView {
        let view = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        view.isEditable = false
        view.isSelectable = true
        view.isHorizontallyResizable = true
        view.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = false
        view.textContainerInset = NSSize(width: 12, height: 12)
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        view.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        return view
    }

    @Test func caretFollowsTypesetGlyphsAcrossTabsEmojiLineEndsAndEOF() throws {
        let line1 = "a\tb🚀c"
        let view = Self.reader("\(line1)\nxy\n")
        let utf16 = Array(0...line1.utf16.count)   // every boundary on line 1, including its newline
        let rects = try utf16.filter { $0 != 4 }.map { try #require(view.insertionCaretRect(atCharacter: $0)) }
        // Strictly left to right along line 1, on one baseline.
        for (left, right) in zip(rects, rects.dropFirst()) {
            #expect(left.minX < right.minX)
            #expect(left.minY == right.minY)
        }
        // The tab advances to its stop (far more than one character cell).
        let cell = rects[1].minX - rects[0].minX
        #expect(rects[2].minX - rects[1].minX > cell * 2)
        // Index 4 is inside the emoji's surrogate pair, whose trailing unit has
        // a null placeholder glyph: the caret snaps to the emoji, and is not
        // mistaken for folded text.
        #expect(view.insertionCaretRect(atCharacter: 4)?.minX == view.insertionCaretRect(atCharacter: 3)?.minX)
        // The caret has the font's height and is thin.
        let font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        #expect(abs(rects[0].height - (font.ascender - font.descender)) <= 1)
        #expect(rects[0].width <= 2)

        // Line 2 starts back at the left margin, one line lower.
        let line2Start = try #require(view.insertionCaretRect(atCharacter: line1.utf16.count + 1))
        #expect(abs(line2Start.minX - rects[0].minX) <= 1)
        #expect(line2Start.minY > rects[0].minY)
        // EOF after a final newline sits on the empty last line.
        let eof = try #require(view.insertionCaretRect(atCharacter: (view.string as NSString).length))
        #expect(eof.minY > line2Start.minY)
        #expect(abs(eof.minX - rects[0].minX) <= 1)

        // EOF without a final newline sits just after the last glyph.
        let unterminated = Self.reader("xy")
        let afterY = try #require(unterminated.insertionCaretRect(atCharacter: 2))
        let onY = try #require(unterminated.insertionCaretRect(atCharacter: 1))
        #expect(afterY.minX > onY.minX && afterY.minY == onY.minY)
        #expect(Self.reader("").insertionCaretRect(atCharacter: 0) == nil)

        // EOF right after a final grapheme cluster whose trailing UTF-16
        // units are null placeholder glyphs: the caret exists, sits after the
        // whole cluster on the same line, and matches the caret placed before
        // an appended character (the true typeset end of the cluster).
        for text in ["🚀", "x👨‍👩‍👧", "xe\u{301}"] {
            let reader = Self.reader(text)
            let length = (text as NSString).length
            let eofRect = try #require(reader.insertionCaretRect(atCharacter: length), "EOF caret after \(text.debugDescription)")
            let start = try #require(reader.insertionCaretRect(atCharacter: 0))
            #expect(eofRect.minY == start.minY)
            #expect(eofRect.minX > start.minX)
            let extended = Self.reader(text + "!")
            #expect(eofRect.minX == extended.insertionCaretRect(atCharacter: length)?.minX,
                    "EOF after \(text.debugDescription) measures the complete cluster")
        }
        // A ZWJ family and a combining accent are single composed characters.
        let composed = Self.reader("a👨‍👩‍👧e\u{301}!")
        let family = "👨‍👩‍👧".utf16.count
        let start = try #require(composed.insertionCaretRect(atCharacter: 1))
        for inside in 2..<(1 + family) { #expect(composed.insertionCaretRect(atCharacter: inside)?.minX == start.minX) }
        let afterFamily = try #require(composed.insertionCaretRect(atCharacter: 1 + family))
        #expect(afterFamily.minX > start.minX)
        #expect(composed.insertionCaretRect(atCharacter: 1 + family + 1)?.minX == afterFamily.minX, "inside e + U+0301")
    }

    @Test func caretIsHiddenInsideFoldedText() throws {
        let source = "fn scan() {\n    work();\n}\nfn next() {}\n"
        let buffer = try SourceBuffer(path: "scan.rs", data: Data(source.utf8))
        let view = Self.reader(source)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = view
        view.layoutManager?.delegate = coordinator
        let open = try #require(source.utf8.firstIndex(of: UInt8(ascii: "{")))
        let close = try #require(source.utf8.firstIndex(of: UInt8(ascii: "}")))
        let start = source.utf8.distance(from: source.utf8.startIndex, to: open)
        let end = source.utf8.distance(from: source.utf8.startIndex, to: close) + 1
        let fold = SourceFold(kind: "function", byteRange: start..<end)
        let snapshot = SyntaxSnapshot(path: "scan.rs", languageID: "rust", languageName: "Rust", highlights: [],
                                      folds: [fold], symbols: [], scopes: [], hasParseErrors: false)
        _ = coordinator.updateSyntax(snapshot, buffer: buffer, resetFolds: true)
        coordinator.applyFoldAttributes()
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let inside = buffer.utf16Offset(forByte: start + 6)   // within `work();`
        #expect(view.insertionCaretRect(atCharacter: inside) == nil)
        // The surviving braces and the next line still have a caret.
        #expect(view.insertionCaretRect(atCharacter: buffer.utf16Offset(forByte: start)) != nil)
        #expect(view.insertionCaretRect(atCharacter: buffer.utf16Offset(forByte: end)) != nil)
        let next = buffer.utf16Offset(forByte: end + 1)
        let nextRect = try #require(view.insertionCaretRect(atCharacter: next))
        let firstRect = try #require(view.insertionCaretRect(atCharacter: 0))
        #expect(nextRect.minY > firstRect.minY, "the folded body collapses but the next line stays below")
    }

    @Test func caretShowsOnlyForAnEmptySelectionInTheFocusedReader() throws {
        let view = Self.reader("let value = 1;\n")
        view.setSelectedRange(NSRange(location: 4, length: 0))
        #expect(view.visibleInsertionCaretRect() == nil, "not in a window")

        // An inactive window never shows the caret, even with the reader focused.
        let inactive = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled],
                                backing: .buffered, defer: true)
        inactive.contentView = view
        #expect(inactive.makeFirstResponder(view))
        #expect(!inactive.isKeyWindow)
        #expect(view.visibleInsertionCaretRect() == nil, "window not key")
        inactive.contentView = nil

        // Headless test runs never grant key status, so a window that reports
        // itself key exercises the real focus and selection gate.
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled],
                               backing: .buffered, defer: true)
        window.contentView = view
        #expect(window.makeFirstResponder(view))
        #expect(view.visibleInsertionCaretRect() == view.insertionCaretRect(atCharacter: 4))
        view.setSelectedRange(NSRange(location: 4, length: 5))
        #expect(view.visibleInsertionCaretRect() == nil, "a highlighted range replaces the caret")
        view.setSelectedRange(NSRange(location: 9, length: 0))
        #expect(view.visibleInsertionCaretRect()?.minX == view.insertionCaretRect(atCharacter: 9)?.minX)
        #expect(window.makeFirstResponder(nil))
        #expect(view.visibleInsertionCaretRect() == nil, "unfocused reader shows no caret")
    }
}

private final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
