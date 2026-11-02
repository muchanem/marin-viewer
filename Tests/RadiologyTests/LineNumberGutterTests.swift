import AppKit
import Testing
@testable import Radiology

/// Exercise the real TextKit visible fragments and native gutter draw, rather
/// than just repeating the numbering predicate in a unit test.
@MainActor
struct LineNumberGutterTests {
    private func harness(_ source: String) throws -> (SourceContainerView, ReaderTextView, LineNumberGutter, SourceBuffer) {
        let buffer = try SourceBuffer(path: "x.rs", data: Data(source.utf8))
        let container = SourceContainerView(frame: NSRect(x: 0, y: 0, width: 500, height: 480))
        let text = SourceCaretTests.reader(source)
        text.frame = NSRect(x: 0, y: 0, width: 500, height: 800)
        text.isVerticallyResizable = true
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = Theme.sourceLineHeight
        paragraph.maximumLineHeight = Theme.sourceLineHeight
        text.textStorage?.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: (source as NSString).length))
        let gutter = LineNumberGutter(textView: text)
        gutter.buffer = buffer
        container.gutter = gutter
        container.addSubview(container.scroll)
        container.addSubview(gutter)
        container.scroll.documentView = text
        container.layoutSubtreeIfNeeded()
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        let used = try #require(text.layoutManager).usedRect(for: text.textContainer!)
        text.setFrameSize(NSSize(width: 500, height: max(480, used.maxY + text.textContainerInset.height * 2)))
        text.setSelectedRange(NSRange(location: 0, length: 0))
        return (container, text, gutter, buffer)
    }

    private func draw(_ gutter: LineNumberGutter) throws {
        let bitmap = try #require(gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds))
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
    }

    @Test func sparseNumbersFollowNativeCaretAndNeverTheScrolledViewport() throws {
        let source = (1...40).map { "// café 🚀 line \($0)" }.joined(separator: "\n")
        let (container, text, gutter, buffer) = try harness(source)
        #expect(gutter.frame.width == 72)
        #expect(container.scroll.frame.minX == gutter.frame.maxX)
        try draw(gutter)
        #expect(gutter.numberedLines == [1, 5, 10, 15, 20])
        let caret = buffer.utf16Offset(forByte: buffer.byteOffset(line: 7)) + 4
        text.setSelectedRange(NSRange(location: caret, length: 0))
        try draw(gutter)
        #expect(gutter.currentLine == 7)
        #expect(gutter.numberedLines == [5, 7, 10, 15, 20], "old non-fifth caret labels disappear")
        container.scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        container.scroll.reflectScrolledClipView(container.scroll.contentView)
        try draw(gutter)
        #expect(gutter.currentLine == 7 && text.selectedRange().location == caret)
        #expect(!gutter.numberedLines.contains(7), "an offscreen caret doesn't label the viewport's first line")
        #expect(gutter.numberedLines.contains(15) && gutter.numberedLines.contains(20))
    }

    @Test func foldedRowsStayUnnumberedAndExpandedNumbersRemainCanonical() throws {
        let lines = (1...4).map { "// header \($0)" } + ["fn folded() {"]
            + (6...14).map { "    work\($0)();" } + ["}"] + (16...20).map { "// after \($0)" }
        let source = lines.joined(separator: "\n")
        let (container, text, gutter, buffer) = try harness(source)
        let start = (source as NSString).range(of: "{").location
        let end = (source as NSString).range(of: "}").location + 1
        let fold = SourceFold(kind: "function", byteRange: buffer.byteOffset(forUTF16: start)..<buffer.byteOffset(forUTF16: end))
        let syntax = SyntaxSnapshot(path: buffer.path, languageID: "rust", languageName: "Rust", highlights: [], folds: [fold],
                                    symbols: [], scopes: [], hasParseErrors: false)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.gutter = gutter
        coordinator.scrollView = container.scroll
        text.layoutManager?.delegate = coordinator
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        coordinator.applyFoldAttributes()
        text.setSelectedRange(NSRange(location: buffer.utf16Offset(forByte: buffer.byteOffset(line: 18)), length: 0))
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        try draw(gutter)
        #expect(gutter.numberedLines.contains(5) && gutter.numberedLines.contains(18))
        #expect(!gutter.numberedLines.contains(10))
        coordinator.toggleFold(fold)
        text.layoutManager?.ensureLayout(for: text.textContainer!)
        try draw(gutter)
        #expect(gutter.numberedLines.contains(10) && gutter.numberedLines.contains(18))
        #expect(gutter.currentLine == 18)
    }
}
