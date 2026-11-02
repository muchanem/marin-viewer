import AppKit
import Foundation
import Testing
@testable import Radiology

/// The faint shade under the caret's function: which function (Tree-sitter,
/// innermost callable), when it clears, and which source lines it covers.
@MainActor
struct FunctionShadeTests {
    static let rust = """
    struct Shape {
        side: u32,
    }

    impl Shape {
        fn area(&self) -> u32 {
            fn square(x: u32) -> u32 {
                x * x
            }
            let f = |y: u32| y + 1;
            f(square(self.side))
        }

        fn name() -> &'static str { "shape" }
    }

    """

    static func byte(_ text: String, line: Int, column: Int) -> Int {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.prefix(line - 1).reduce(0) { $0 + $1.utf8.count + 1 } + column
    }

    @Test func innermostCallableNotContainers() async throws {
        let buffer = try SourceBuffer(path: "shape.rs", data: Data(Self.rust.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        func function(_ line: Int, _ column: Int) -> String? {
            syntax.innermostFunction(at: Self.byte(Self.rust, line: line, column: column))?.name
        }
        #expect(function(8, 16) == "square", "a nested fn is innermost")
        #expect(function(10, 22) == "area", "a closure is not a named function; its fn is")
        #expect(function(6, 4) == "area", "the signature line belongs to the function")
        #expect(function(14, 32) == "name")
        #expect(function(13, 0) == nil, "between methods: the impl is not shaded")
        #expect(function(2, 6) == nil, "inside a struct")
        #expect(function(1, 0) == nil)
        // Half-open: the byte after `area`'s closing brace is outside it.
        let areaEnd = try #require(syntax.symbols.first { $0.name == "area" }).byteRange.upperBound
        #expect(syntax.innermostFunction(at: areaEnd - 1)?.name == "area")
        #expect(syntax.innermostFunction(at: areaEnd) == nil)

        let python = "class Shape:\n    def area(self):\n        def inner():\n            return 1\n        return inner()\n"
        let pyBuffer = try SourceBuffer(path: "shape.py", data: Data(python.utf8))
        let pySyntax = try #require(try await SyntaxWorker().parse(pyBuffer))
        #expect(pySyntax.innermostFunction(at: Self.byte(python, line: 4, column: 14))?.name == "inner")
        #expect(pySyntax.innermostFunction(at: Self.byte(python, line: 5, column: 10))?.name == "area")
        #expect(pySyntax.innermostFunction(at: Self.byte(python, line: 1, column: 2)) == nil)
    }

    @Test func followsTheCaretNotScrollingAndClearsOnFileAndRepositoryChanges() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-shade-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(Self.rust.utf8).write(to: root.appending(path: "shape.rs"))
        try Data("# notes\n".utf8).write(to: root.appending(path: "NOTES.md"))
        let model = AppModel(preferences: try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString)))
        model.openRepository(root)
        try await IndexingTests.waitUntil { !model.isOpening }
        model.openFile("shape.rs")
        try await IndexingTests.waitUntil { model.syntax?.path == "shape.rs" }
        let syntax = try #require(model.syntax)
        let area = try #require(syntax.symbols.first { $0.name == "area" }).byteRange
        let square = try #require(syntax.symbols.first { $0.name == "square" }).byteRange

        model.caretMoved(to: Self.byte(Self.rust, line: 11, column: 12))
        #expect(model.currentFunctionRange == area)
        // Passive scrolling (restoration position only) keeps the caret's function.
        model.updatePosition(path: "shape.rs", byteOffset: 0, line: 1)
        model.refreshContext()
        #expect(model.currentFunctionRange == area)
        model.caretMoved(to: Self.byte(Self.rust, line: 8, column: 16))
        #expect(model.currentFunctionRange == square)
        model.caretMoved(to: Self.byte(Self.rust, line: 13, column: 0))
        #expect(model.currentFunctionRange == nil, "between methods")

        model.caretMoved(to: Self.byte(Self.rust, line: 11, column: 12))
        #expect(model.currentFunctionRange == area)
        model.openFile("NOTES.md")
        #expect(model.currentFunctionRange == nil, "a file change clears at once, before the new file loads")
        try await IndexingTests.waitUntil { model.source?.path == "NOTES.md" }
        #expect(model.currentFunctionRange == nil, "no structure, no shade")

        model.openFile("shape.rs")
        try await IndexingTests.waitUntil { model.syntax?.path == "shape.rs" }
        model.caretMoved(to: Self.byte(Self.rust, line: 11, column: 12))
        #expect(model.currentFunctionRange == area)
        model.openRepository(root)
        #expect(model.currentFunctionRange == nil, "a repository change clears")
    }

    @Test func bandCoversTheFunctionsVisibleLinesAndRespectsFolds() async throws {
        let buffer = try SourceBuffer(path: "shape.rs", data: Data(Self.rust.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let area = try #require(syntax.symbols.first { $0.name == "area" })
        let view = SourceCaretTests.reader(Self.rust)
        let layout = try #require(view.layoutManager)
        func fragment(line: Int) -> NSRect {
            let glyph = layout.glyphIndexForCharacter(at: buffer.utf16Offset(forByte: buffer.byteOffset(line: line)))
            return layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).offsetBy(dx: 0, dy: view.textContainerOrigin.y)
        }
        let everything = NSRect(x: 0, y: 0, width: 800, height: 10_000)
        #expect(view.functionShadeRect(in: everything) == nil, "no function, no band")

        view.functionShadeRange = buffer.utf16Range(forByteRange: area.byteRange)
        let band = try #require(view.functionShadeRect(in: everything))
        #expect(band.minY == fragment(line: 6).minY, "starts on the signature line")
        #expect(band.maxY == fragment(line: 12).maxY, "ends on the closing-brace line")
        #expect(band.minX == 0 && band.width >= 800, "full width, like the current-line tint")

        // Bounded by what is visible: a viewport over lines 8–9 bands only those.
        let viewport = NSRect(x: 0, y: fragment(line: 8).minY, width: 800, height: fragment(line: 9).maxY - fragment(line: 8).minY)
        let clipped = try #require(view.functionShadeRect(in: viewport))
        #expect(clipped.minY >= fragment(line: 8).minY - 1 && clipped.maxY <= fragment(line: 9).maxY + 1)

        // Folding `area` collapses its body: the band shrinks to one visible line.
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = view
        layout.delegate = coordinator
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)   // default: function bodies folded
        coordinator.applyFoldAttributes()
        layout.ensureLayout(for: view.textContainer!)
        let folded = try #require(view.functionShadeRect(in: everything))
        #expect(folded.height < band.height / 3)
        #expect(abs(folded.minY - fragment(line: 6).minY) < 1)

        // A stale range past the text never draws.
        view.functionShadeRange = NSRange(location: 0, length: (Self.rust as NSString).length + 10)
        #expect(view.functionShadeRect(in: everything) == nil)
    }
}
