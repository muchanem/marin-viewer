import AppKit
import Testing
@testable import Radiology

@MainActor
struct SourceScrollViewTests {
    @Test func realAppFoldPerformanceProbe() async throws {
        guard ProcessInfo.processInfo.environment["RADIOLOGY_REAL_FOLD_BENCHMARK"] == "1" else { return }
        let url = URL(fileURLWithPath: "/Users/agentzero/codebase/tkos/modules/agent/ffi/src/app.rs")
        guard let data = try? Data(contentsOf: url) else { return }
        let buffer = try SourceBuffer(path: "modules/agent/ffi/src/app.rs", data: data)
        let snapshot = try #require(try await SyntaxWorker().parse(buffer))
        func functionFold(at line: Int) throws -> SourceFold {
            try #require(snapshot.folds.first {
                $0.kind == "function" && buffer.line(atByte: $0.byteRange.lowerBound) == line
            })
        }
        let samples = [("large", try functionFold(at: 1453)),
                       ("medium", try functionFold(at: 1734)),
                       ("tiny", try functionFold(at: 1812))]
        let text = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = true
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.containerSize = text.maxSize
        text.textContainer?.widthTracksTextView = false
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        text.string = buffer.text
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        text.layoutManager?.delegate = coordinator
        _ = coordinator.updateSyntax(snapshot, buffer: buffer, resetFolds: true)
        coordinator.applyFoldAttributes()
        let layout = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        layout.ensureLayout(for: container)

        let clock = ContinuousClock()
        for (name, fold) in samples {
            var durations: [Double] = []
            for _ in 0..<3 {
                var start = clock.now
                coordinator.toggleFold(fold)
                layout.ensureLayout(for: container)
                durations.append(Double((start.duration(to: clock.now)).components.attoseconds) / 1e18)
                start = clock.now
                coordinator.toggleFold(fold)
                layout.ensureLayout(for: container)
                durations.append(Double((start.duration(to: clock.now)).components.attoseconds) / 1e18)
            }
            print("APP_RS_\(name.uppercased())_FOLD_SECONDS", durations)
            #expect(coordinator.isFolded(fold))
        }
    }
    @Test func collapsedFunctionMetersUseCanonicalHiddenLinesAndALogarithmicScale() throws {
        func delimited(bodyLines: Int, lineEnding: String = "\n") throws -> (SourceBuffer, SourceFold) {
            let body = (0..<bodyLines).map { "    work\($0)();" }.joined(separator: lineEnding)
            let source = "fn scan() {\(lineEnding)\(body)\(lineEnding)}\(lineEnding)"
            let buffer = try SourceBuffer(path: "scan.rs", data: Data(source.utf8))
            let start = try #require(buffer.data.range(of: Data("{".utf8))?.lowerBound)
            let end = try #require(buffer.data.range(of: Data("}".utf8), options: .backwards)?.upperBound)
            return (buffer, SourceFold(kind: "function", byteRange: start..<end))
        }

        let tiny = try delimited(bodyLines: 1, lineEnding: "\r\n")
        let medium = try delimited(bodyLines: 19)
        let large = try delimited(bodyLines: 199)
        #expect(LineNumberGutter.hiddenSourceLineCount(for: tiny.1, in: tiny.0) == 2)
        #expect(LineNumberGutter.hiddenSourceLineCount(for: medium.1, in: medium.0) == 20)
        #expect(LineNumberGutter.hiddenSourceLineCount(for: large.1, in: large.0) == 200)
        let widths = [2, 20, 200].map(LineNumberGutter.functionMeterWidth(hiddenLineCount:))
        #expect(widths[0] < widths[1] && widths[1] < widths[2])
        #expect(widths[0] >= 6 && widths[2] <= 22)
        #expect(LineNumberGutter.functionMeterWidth(hiddenLineCount: 2_000)
                == LineNumberGutter.functionMeterWidth(hiddenLineCount: 256))
        #expect(LineNumberGutter.foldCountLabel(hiddenLineCount: 603) == "603")
        #expect(LineNumberGutter.foldCountLabel(hiddenLineCount: 10_200) == "9999+")
    }

    @Test func functionMeterHandlesIndentationUnicodeMultilineSignaturesAndEmptyBodies() throws {
        let python = "def render(\n    value: str,\n):\n    chest = \"胸部\"\r\n    return chest\r\n"
        let pythonBuffer = try SourceBuffer(path: "scan.py", data: Data(python.utf8))
        let start = try #require(pythonBuffer.data.range(of: Data("    chest".utf8))?.lowerBound)
        let end = pythonBuffer.data.count - 2
        let pythonFold = SourceFold(kind: "function", byteRange: start..<end)
        #expect(LineNumberGutter.headerLine(for: pythonFold, in: pythonBuffer) == 3)
        #expect(LineNumberGutter.hiddenSourceLineCount(for: pythonFold, in: pythonBuffer) == 2)

        let emptyBuffer = try SourceBuffer(path: "empty.rs", data: Data("fn empty() {}\n".utf8))
        let open = try #require(emptyBuffer.data.range(of: Data("{".utf8))?.lowerBound)
        let close = try #require(emptyBuffer.data.range(of: Data("}".utf8))?.upperBound)
        let emptyFold = SourceFold(kind: "function", byteRange: open..<close)
        #expect(LineNumberGutter.headerLine(for: emptyFold, in: emptyBuffer) == 1)
        #expect(LineNumberGutter.hiddenSourceLineCount(for: emptyFold, in: emptyBuffer) == 0)
    }

    @Test func aFreshDocumentJumpSizesTheWholeFileBeforeRestoringPosition() throws {
        let scroll = SourceScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        let text = ReaderTextView(frame: .zero)
        text.isEditable = false
        text.textContainerInset = NSSize(width: Theme.sourceInset, height: Theme.sourceInset)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = true
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.containerSize = text.maxSize
        text.textContainer?.widthTracksTextView = false
        text.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        text.string = String(repeating: "source line\n", count: 300)
        scroll.documentView = text
        let offset = "source line\n".utf16.count * 150
        scroll.pendingLocation = offset
        scroll.layout()
        let layout = try #require(text.layoutManager)
        let glyph = layout.glyphIndexForCharacter(at: offset)
        let expectedY = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        #expect(abs(scroll.contentView.bounds.minY - expectedY) < 1)
        #expect(text.frame.height > expectedY + scroll.contentSize.height)
        #expect(scroll.contentView.bounds.minX == 0)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.scrollView = scroll
        coordinator.buffer = try SourceBuffer(path: "source", data: Data(text.string.utf8))
        var savedOffset: Int?
        var caretOffset: Int?
        coordinator.onPosition = { byte, _ in savedOffset = byte }
        coordinator.onCaret = { caretOffset = $0 }
        coordinator.didScroll(Notification(name: NSView.boundsDidChangeNotification))
        #expect(savedOffset == offset, "Restoration must not drift up by one line on each return")
        #expect(caretOffset == nil, "passive scrolling must not replace the semantic caret")
        text.setSelectedRange(NSRange(location: offset + 2, length: 0))
        coordinator.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification,
                                                            object: text))
        #expect(caretOffset == offset + 2, "selection changes update the semantic caret")
        scroll.pendingLocation = 0
        scroll.layout()
        #expect(scroll.contentView.bounds.minY == 0)
    }

    @Test func structuralFoldUsesSourceBufferConversionAtTextKitBoundary() throws {
        let source = "func scan() {\n    let value = \"胸部\"\n    print(value)\n}\n"
        let data = Data(source.utf8)
        let buffer = try SourceBuffer(path: "Fold.swift", data: data)
        let start = try #require(data.range(of: Data("{".utf8))?.lowerBound)
        let end = try #require(data.range(of: Data("}".utf8), options: .backwards)?.upperBound)
        let fold = SourceFold(kind: "function", byteRange: start..<end)
        let text = ReaderTextView()
        text.textStorage?.setAttributedString(NSAttributedString(string: source))
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.buffer = buffer
        coordinator.syntax = SyntaxSnapshot(path: buffer.path, languageID: "swift", languageName: "Swift", highlights: [],
                                               folds: [fold], symbols: [], scopes: [], hasParseErrors: false)
        coordinator.toggleFold(fold)
        let hidden = buffer.utf16Range(forByteRange: (start + 1)..<(end - 1))
        let layout = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        layout.ensureLayout(for: container)
        #expect(layout.notShownAttribute(forGlyphAt: layout.glyphIndexForCharacter(at: hidden.location)))
        #expect(!LineNumberGutter.shouldDrawLine(atUTF16: hidden.location, layout: layout,
                                                 utf16Count: buffer.utf16Count),
                "A folded source line must not paint its line number on the surviving fragment")
        #expect(LineNumberGutter.shouldDrawLine(atUTF16: 0, layout: layout, utf16Count: buffer.utf16Count))
        // The braces themselves stay visible, so the collapsed body reads as `{}`.
        #expect(!layout.notShownAttribute(forGlyphAt: layout.glyphIndexForCharacter(at: hidden.location - 1)))
        coordinator.toggleFold(fold)
    }

    @Test func sixHundredLineMultilineRustFunctionCompactsWithoutBlankFragments() throws {
        let prefix = String(repeating: "// preceding source row\n", count: 8)
        let signature = """
        async fn open(
            &self,
            executor_id: &str,
            realtime: Option<String>,
            fork_from: Option<&str>,
        ) -> Result<String, String>
        {
        """
        let body = (0..<607).map { index in
            index == 300 ? "    let closure = || { nested(); };" : "    work_\(index)();"
        }.joined(separator: "\n")
        let suffix = """

        }

        fn complete_tool() {}

        fn request_observe() {}
        """
        let source = prefix + signature + "\n" + body + suffix
        let buffer = try SourceBuffer(path: "modules/agent/ffi/src/app.rs", data: Data(source.utf8))
        let open = try #require(buffer.data.range(of: Data("{\n    work_0".utf8))?.lowerBound)
        let closeNeedle = Data("\n}\n\nfn complete_tool".utf8)
        let close = try #require(buffer.data.range(of: closeNeedle)?.lowerBound) + 2
        let fold = SourceFold(kind: "function", byteRange: open..<close)

        let text = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = true
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.containerSize = text.maxSize
        text.textContainer?.widthTracksTextView = false
        let font = NSFont.monospacedSystemFont(ofSize: 18, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 28
        paragraph.maximumLineHeight = 28
        text.textStorage?.setAttributedString(NSAttributedString(string: source,
                                                                  attributes: [.font: font, .paragraphStyle: paragraph]))
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.buffer = buffer
        coordinator.syntax = SyntaxSnapshot(path: buffer.path, languageID: "rust", languageName: "Rust",
                                            highlights: [], folds: [fold], symbols: [], scopes: [],
                                            hasParseErrors: false)
        coordinator.toggleFold(fold)

        let layout = try #require(text.layoutManager)
        let container = try #require(text.textContainer)
        layout.ensureLayout(for: container)
        let collapsedHeight = layout.usedRect(for: container).height
        #expect(collapsedHeight < 28 * 25,
                "607 hidden rows must not survive as hundreds of empty TextKit fragments")
        let hidden = buffer.utf16Range(forByteRange: (open + 1)..<(close - 1))
        let hiddenNewlineRange = (source as NSString).range(of: "\n", options: [], range: hidden)
        #expect(hiddenNewlineRange.location != NSNotFound)
        let hiddenNewline = hiddenNewlineRange.location
        let hiddenGlyph = layout.glyphIndexForCharacter(at: hiddenNewline)
        #expect(layout.propertyForGlyph(at: hiddenGlyph).contains(.null))
        #expect(coordinator.layoutManager(layout, shouldUse: .lineBreak,
                                          forControlCharacterAt: hiddenNewline) == .zeroAdvancement,
                "hidden newlines must not continue creating line fragments")

        coordinator.toggleFold(fold)
        layout.ensureLayout(for: container)
        #expect(layout.usedRect(for: container).height > collapsedHeight * 20)
        text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        coordinator.toggleFold(fold)
        layout.ensureLayout(for: container)
        #expect(layout.usedRect(for: container).height < 28 * 25,
                "font changes followed by re-collapse remain compact")
    }

    /// Indentation-delimited bodies have no braces to leave behind, so the
    /// whole captured range collapses instead of stranding its first character.
    @Test func indentationDelimitedFoldHidesItsWholeRange() throws {
        let source = "def render():\n    parts = [\"胸部\"]\n    return parts\n"
        let data = Data(source.utf8)
        let buffer = try SourceBuffer(path: "Fold.py", data: data)
        let start = try #require(data.range(of: Data("parts = [".utf8))?.lowerBound)
        let end = data.count - 1
        let fold = SourceFold(kind: "block", byteRange: start..<end)
        let text = ReaderTextView()
        text.textStorage?.setAttributedString(NSAttributedString(string: source))
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.buffer = buffer
        coordinator.syntax = SyntaxSnapshot(path: buffer.path, languageID: "python", languageName: "Python",
                                            highlights: [], folds: [fold], symbols: [], scopes: [],
                                            hasParseErrors: false)
        coordinator.toggleFold(fold)
        let hidden = buffer.utf16Range(forByteRange: start..<end)
        let layout = try #require(text.layoutManager)
        layout.ensureLayout(for: try #require(text.textContainer))
        #expect(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: hidden.location)).contains(.null))
        #expect(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: NSMaxRange(hidden) - 1)).contains(.null))
        #expect(buffer.text == source, "folding must not modify the backing source")
        coordinator.toggleFold(fold)
    }

    @Test func foldToDefinitionsKeepsContainersOpenAndNavigationRevealsTargets() throws {
        let source = "impl PreparedApp {\n    fn image() {\n        work();\n    }\n}\n"
        let buffer = try SourceBuffer(path: "app.rs", data: Data(source.utf8))
        let typeRange = 17..<source.utf8.count
        let functionStart = try #require(buffer.data.range(of: Data("{".utf8), in: 18..<buffer.data.count)?.lowerBound)
        let functionEnd = try #require(buffer.data.range(of: Data("}".utf8))?.upperBound)
        let functionRange = functionStart..<functionEnd
        let symbolStart = try #require(buffer.data.range(of: Data("image".utf8))?.lowerBound)
        let symbol = DocumentSymbol(name: "image", kind: "function", byteRange: 23..<functionEnd,
                                    selectionByteRange: symbolStart..<(symbolStart + 5), depth: 1)
        let typeFold = SourceFold(kind: "type", byteRange: typeRange)
        let functionFold = SourceFold(kind: "function", byteRange: functionRange)
        let text = ReaderTextView()
        text.textStorage?.setAttributedString(NSAttributedString(string: source))
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.buffer = buffer
        coordinator.syntax = SyntaxSnapshot(path: buffer.path, languageID: "rust", languageName: "Rust",
                                            highlights: [], folds: [typeFold, functionFold], symbols: [symbol],
                                            scopes: [], hasParseErrors: false)
        coordinator.foldToDefinitions()
        #expect(coordinator.isFolded(functionFold))
        #expect(!coordinator.isFolded(typeFold))
        coordinator.reveal(byteOffset: 44)
        #expect(!coordinator.isFolded(functionFold))
        coordinator.toggleFold(typeFold)
        #expect(coordinator.isFolded(typeFold))
        coordinator.reveal(byteOffset: symbolStart)
        #expect(!coordinator.isFolded(typeFold), "A nested declaration hidden by its parent must be revealed before navigation")
    }

    @Test func defaultFunctionFoldsApplyOnceAndExplicitCollapseRestoresThem() throws {
        let source = "class Scan {\n    func render() {\n        work()\n    }\n}\n"
        let buffer = try SourceBuffer(path: "Scan.swift", data: Data(source.utf8))
        let typeFold = SourceFold(kind: "type", byteRange: 11..<source.utf8.count)
        let bodyStart = try #require(buffer.data.range(of: Data("{\n        work".utf8))?.lowerBound)
        let bodyEnd = try #require(buffer.data.range(of: Data("    }".utf8))?.upperBound)
        let functionFold = SourceFold(kind: "function", byteRange: bodyStart..<bodyEnd)
        let snapshot = SyntaxSnapshot(path: buffer.path, languageID: "swift", languageName: "Swift",
                                      highlights: [], folds: [typeFold, functionFold], symbols: [], scopes: [],
                                      hasParseErrors: false)
        let text = ReaderTextView()
        text.string = source
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text

        #expect(coordinator.updateSyntax(snapshot, buffer: buffer, resetFolds: true))
        #expect(coordinator.isFolded(functionFold))
        #expect(!coordinator.isFolded(typeFold), "containers stay open so nested signatures remain visible")

        coordinator.toggleFold(functionFold)
        #expect(!coordinator.isFolded(functionFold))
        #expect(!coordinator.updateSyntax(snapshot, buffer: buffer, resetFolds: false))
        #expect(!coordinator.isFolded(functionFold), "ordinary view updates must preserve manual expansion")

        coordinator.collapseFunctions()
        #expect(coordinator.isFolded(functionFold), "the explicit action re-collapses expanded functions")
        coordinator.reveal(byteOffset: bodyStart + 2)
        #expect(!coordinator.isFolded(functionFold), "a pending or committed jump must win over default folding")
    }

    @Test func defaultFoldStateDoesNotTouchTextKitBeforeNewBufferIsInstalled() throws {
        let oldSource = "fn old() {}\n"
        let newSource = "fn replacement() {\n    one();\n    two();\n}\n"
        let buffer = try SourceBuffer(path: "replacement.rs", data: Data(newSource.utf8))
        let bodyStart = try #require(buffer.data.range(of: Data("{".utf8))?.lowerBound)
        let bodyEnd = buffer.data.count - 1
        let fold = SourceFold(kind: "function", byteRange: bodyStart..<bodyEnd)
        let snapshot = SyntaxSnapshot(path: buffer.path, languageID: "rust", languageName: "Rust",
                                      highlights: [], folds: [fold], symbols: [], scopes: [],
                                      hasParseErrors: false)
        let text = ReaderTextView()
        text.string = oldSource
        _ = text.layoutManager?.glyphRange(for: text.textContainer!)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text

        #expect(coordinator.updateSyntax(snapshot, buffer: buffer, resetFolds: true))
        #expect(coordinator.isFolded(fold))
        #expect(text.string == oldSource,
                "default-fold discovery must not invalidate or mutate TextKit until SourceViewer installs the new buffer")
    }

    @Test func destinationHighlightRestartsAndClearsWithoutChangingText() async throws {
        let source = "fn first() {}\nfn second() {}\n"
        let text = ReaderTextView()
        text.string = source
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.flashDestination(atUTF16: 3, hold: .milliseconds(80))
        #expect(text.destinationHighlightRange?.location == 3)
        coordinator.flashDestination(atUTF16: 18, hold: .milliseconds(20))
        #expect(text.destinationHighlightRange?.location == 18)
        #expect(text.string == source)
        // Main-actor timers can be delayed while the full suite exercises
        // parsing and AppKit concurrently; allow ample time beyond the 230 ms
        // hold-and-fade duration while still asserting automatic cleanup.
        try await Task.sleep(for: .seconds(2))
        #expect(text.destinationHighlightRange == nil)
        #expect(text.destinationHighlightAlpha == 0)
        #expect(text.string == source)
    }

    @Test func semanticOccurrenceDecorationDoesNotMutateTextOrSelection() {
        let source = "let value = value + 1\n"
        let text = ReaderTextView()
        text.string = source
        text.setSelectedRange(NSRange(location: 4, length: 5))
        text.occurrenceHighlightRanges = [NSRange(location: 4, length: 5), NSRange(location: 12, length: 5)]
        text.activeOccurrenceHighlightRange = NSRange(location: 4, length: 5)
        text.pinnedOccurrenceDecorations = [
            .init(ranges: [NSRange(location: 4, length: 5), NSRange(location: 12, length: 5)], colorSlot: 2),
        ]

        #expect(text.string == source)
        #expect(text.selectedRange() == NSRange(location: 4, length: 5))
        #expect(text.layoutManager?.temporaryAttributes(atCharacterIndex: 4, effectiveRange: nil).isEmpty == true,
                "occurrence paint must not share temporary attributes with hover or find")

        text.occurrenceHighlightRanges = []
        text.activeOccurrenceHighlightRange = nil
        text.pinnedOccurrenceDecorations = []
        #expect(text.string == source)
        #expect(text.selectedRange() == NSRange(location: 4, length: 5))
    }
}
