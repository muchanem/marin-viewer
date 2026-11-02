import AppKit
import Foundation
import Testing
@testable import Radiology

/// Hide Tests as a presentation projection: canonical ranges, TextKit null
/// glyphs and gutter line numbers, coexistence with folds, exact copy bytes,
/// and the model's reveal/navigation/identity contract.
@MainActor
struct TestCodePresentationTests {
    /// tkos app.rs:802–834 in miniature, with non-ASCII bytes before and inside.
    static let rust = """
    // 🩻 production prelude
    impl HarnessApp {
        #[cfg(test)]
        pub(crate) fn detached_for_test() -> Arc<Self> {
            let marker = "🧪";
            Arc::new(Self { marker })
        }
        fn create_durable_agent(&self) -> u8 {
            1
        }
    }
    fn tail() {}

    """

    private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        #expect(condition(), "Async model operation timed out")
    }

    /// Canonical source lines of the TextKit fragments that show anything,
    /// computed the way the gutter labels them.
    private static func visibleLines(_ view: NSTextView, buffer: SourceBuffer) -> [Int] {
        guard let layout = view.layoutManager, let container = view.textContainer else { return [] }
        layout.ensureLayout(for: container)
        var lines: [Int] = []
        layout.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)) { _, _, _, glyphs, _ in
            guard let glyph = LineNumberGutter.firstVisibleGlyph(in: glyphs, layout: layout) else { return }
            let line = buffer.line(atByte: buffer.byteOffset(forUTF16: layout.characterIndexForGlyph(at: glyph)))
            if lines.last != line { lines.append(line) }
        }
        return lines
    }

    @Test func presentationKeepsTheHeaderLineAndHidesTheRestExactly() async throws {
        let buffer = try SourceBuffer(path: "app.rs", data: Data(Self.rust.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let identity = SourceContentIdentity(buffer.data)
        let presentation = TestCodePresentation(regions: syntax.testRegions, revealed: [], buffer: buffer, sourceIdentity: identity)
        let region = try #require(presentation.regions.first)
        #expect(presentation.regions.count == 1)
        #expect(region.headerLine == 3 && region.hiddenLineCount == 4 && region.isHidden)
        #expect(String(decoding: buffer.data[region.headerByteRange], as: UTF8.self) == "    #[cfg(test)]")
        // Hidden text starts at the header's newline and ends at the helper's
        // closing brace; line 8's newline and code stay outside.
        #expect(buffer.data[region.hiddenByteRange.lowerBound] == 0x0A)
        #expect(String(decoding: buffer.data[region.hiddenByteRange], as: UTF8.self).hasSuffix("🧪\";\n        Arc::new(Self { marker })\n    }"))
        #expect(buffer.line(atByte: region.hiddenByteRange.upperBound) == 7)
        #expect(presentation.matches(path: "app.rs", sourceIdentity: identity))
        #expect(!presentation.matches(path: "copy.rs", sourceIdentity: identity), "identical bytes at another path are another document")
        #expect(!presentation.matches(path: "app.rs", sourceIdentity: SourceContentIdentity(Data("x".utf8))))
        let helper = try #require(syntax.symbols.first { $0.name == "detached_for_test" })
        let production = try #require(syntax.symbols.first { $0.name == "create_durable_agent" })
        #expect(presentation.hides(helper.byteRange) && !presentation.hides(production.byteRange))
        let revealed = TestCodePresentation(regions: syntax.testRegions, revealed: [region.id], buffer: buffer, sourceIdentity: identity)
        #expect(revealed.hiddenRegions.isEmpty && !revealed.hides(helper.byteRange))
    }

    @Test func textKitHidesTestLinesKeepsCanonicalNumbersCopyBytesAndFolds() async throws {
        let buffer = try SourceBuffer(path: "app.rs", data: Data(Self.rust.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let identity = SourceContentIdentity(buffer.data)
        let presentation = TestCodePresentation(regions: syntax.testRegions, revealed: [], buffer: buffer, sourceIdentity: identity)
        let view = SourceCaretTests.reader(Self.rust)
        let gutter = LineNumberGutter(textView: view)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = view
        coordinator.gutter = gutter
        view.layoutManager?.delegate = coordinator
        #expect(Self.visibleLines(view, buffer: buffer) == Array(1...12))

        // Test code alone: the header stays, lines 4–7 vanish, production resumes at 8.
        coordinator.buffer = buffer
        coordinator.syntax = syntax
        #expect(coordinator.setTestPresentation(presentation))
        #expect(!coordinator.setTestPresentation(presentation), "an equal presentation is not reapplied")
        coordinator.applyFoldAttributes()
        #expect(Self.visibleLines(view, buffer: buffer) == [1, 2, 3, 8, 9, 10, 11, 12])
        let layout = try #require(view.layoutManager)
        let emoji = (Self.rust as NSString).range(of: "🧪").location
        #expect(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: emoji)).contains(.null))
        let header = buffer.utf16Offset(forByte: buffer.byteOffset(line: 3)) + 4
        #expect(!layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: header)).contains(.null))
        #expect(coordinator.recededRun(at: header).isReceded, "the header line recedes")
        #expect(!coordinator.recededRun(at: buffer.utf16Offset(forByte: buffer.byteOffset(line: 8)) + 4).isReceded)
        let region = try #require(presentation.regions.first)
        #expect(gutter.testMarkers == [LineNumberGutter.TestMarker(id: region.id, headerLine: 3, hiddenLineCount: 4)])
        let label = try #require(view.testRegionLabels.first)
        #expect(label.title == "Test code · 4 lines hidden" && label.isHidden)
        #expect(label.headerEnd == buffer.utf16Offset(forByte: region.headerByteRange.upperBound))
        let labelRect = try #require(view.testLabelRect(for: label, in: NSRect(x: 0, y: 0, width: 2_000, height: 2_000)))
        let headerGlyph = layout.glyphIndexForCharacter(at: label.headerEnd - 1)
        #expect(labelRect.minX > layout.boundingRect(forGlyphRange: NSRange(location: headerGlyph, length: 1), in: view.textContainer!).maxX)

        // Copy and storage are untouched source bytes.
        #expect(view.string == Self.rust)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("RadiologyTests." + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.setSelectedRange(NSRange(location: 0, length: (Self.rust as NSString).length))
        pasteboard.clearContents()
        // The read-only plain-text view writes AppKit's legacy string type.
        let stringType = try #require(view.writablePasteboardTypes.first { $0.rawValue == "NSStringPboardType" })
        #expect(view.writeSelection(to: pasteboard, type: stringType))
        #expect((pasteboard.string(forType: stringType) ?? pasteboard.string(forType: .string)) == Self.rust)

        // Default function folds join the same disjoint union.
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        coordinator.applyFoldAttributes()
        #expect(Self.visibleLines(view, buffer: buffer) == [1, 2, 3, 8, 11, 12])
        let productionFold = try #require(syntax.folds.first { $0.kind == "function" && buffer.line(atByte: $0.byteRange.lowerBound) == 8 })
        coordinator.toggleFold(productionFold)
        #expect(Self.visibleLines(view, buffer: buffer) == [1, 2, 3, 8, 9, 10, 11, 12], "a manual expansion under hidden tests")

        // Showing tests again keeps every fold decision: the helper's default
        // fold and the reader's manual expansion both survive.
        #expect(coordinator.setTestPresentation(nil))
        coordinator.applyFoldAttributes()
        #expect(Self.visibleLines(view, buffer: buffer) == [1, 2, 3, 4, 8, 9, 10, 11, 12])
        #expect(gutter.testMarkers.isEmpty && view.testRegionLabels.isEmpty)
        #expect(!coordinator.recededRun(at: header).isReceded)
        #expect(!coordinator.isFolded(productionFold))
        #expect(coordinator.setTestPresentation(presentation))
        coordinator.applyFoldAttributes()
        #expect(Self.visibleLines(view, buffer: buffer) == [1, 2, 3, 8, 9, 10, 11, 12])

        // Navigation into a fold inside hidden test code: once the model has
        // revealed the region, the viewer's fold reveal opens the helper body.
        let revealed = TestCodePresentation(regions: syntax.testRegions, revealed: [region.id], buffer: buffer, sourceIdentity: identity)
        #expect(coordinator.setTestPresentation(revealed))
        coordinator.reveal(byteOffset: buffer.byteOffset(line: 5) + 8, applyAttributes: false)
        coordinator.applyFoldAttributes()
        #expect(Self.visibleLines(view, buffer: buffer) == Array(1...12))
        #expect(view.testRegionLabels.first?.title == "Hide test code")
    }

    @Test func labelHitIdentityChangesEvenWhenGeometryDoesNot() throws {
        let view = SourceCaretTests.reader("// a\n#[cfg(test)]\nfn helper() {}\n")
        let headerEnd = (view.string as NSString).range(of: "#[cfg(test)]").location + 12
        view.testRegionLabels = [.init(id: 5, headerEnd: headerEnd, hiddenLineCount: 1, isHidden: true)]
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        defer { image.unlockFocus() }
        view.drawBackground(in: view.bounds)
        let first = try #require(view.testLabelHitRects.first)
        let point = NSPoint(x: first.rect.midX, y: first.rect.midY)
        #expect(view.testRegionLabel(at: point) == 5)
        // A second file's prefix has another UTF-8 length but the same typeset
        // line height/header geometry. The label's region ID must change too.
        view.textStorage?.setAttributedString(NSAttributedString(string: "// 🚀\n#[cfg(test)]\nfn helper() {}\n",
                                                                 attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)]))
        let nextEnd = (view.string as NSString).range(of: "#[cfg(test)]").location + 12
        view.testRegionLabels = [.init(id: 8, headerEnd: nextEnd, hiddenLineCount: 1, isHidden: true)]
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        view.drawBackground(in: view.bounds)
        #expect(view.testLabelHitRects.first?.rect == first.rect)
        #expect(view.testRegionLabel(at: point) == 8)
    }

    @Test func nestedTestLabelCannotPaintOrHitAFoldedProductionRow() async throws {
        let text = "fn outer() {\n    #[cfg(test)]\n    fn helper() {}\n    production();\n}\n"
        let buffer = try SourceBuffer(path: "nested.rs", data: Data(text.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let view = SourceCaretTests.reader(text)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = view
        view.layoutManager?.delegate = coordinator
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        _ = coordinator.setTestPresentation(TestCodePresentation(regions: syntax.testRegions, revealed: [], buffer: buffer,
                                                               sourceIdentity: SourceContentIdentity(buffer.data)))
        coordinator.applyFoldAttributes()
        let label = try #require(view.testRegionLabels.first)
        let layout = try #require(view.layoutManager)
        layout.ensureLayout(for: view.textContainer!)
        #expect(layout.propertyForGlyph(at: layout.glyphIndexForCharacter(at: label.headerEnd - 1)).contains(.null))
        #expect(view.testLabelRect(for: label, in: view.bounds) == nil)
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        defer { image.unlockFocus() }
        view.drawBackground(in: view.bounds)
        #expect(view.testLabelHitRects.isEmpty)
        let outer = try #require(syntax.folds.first { $0.kind == "function" && buffer.line(atByte: $0.byteRange.lowerBound) == 1 })
        coordinator.toggleFold(outer)
        layout.ensureLayout(for: view.textContainer!)
        #expect(view.testLabelRect(for: label, in: view.bounds) != nil)
        view.drawBackground(in: view.bounds)
        #expect(view.testLabelHitRects.first?.id == label.id)
    }

    @Test func unionMergesOverlappingTouchingAndContainedRanges() {
        let ranges = [NSRange(location: 10, length: 5), NSRange(location: 0, length: 3), NSRange(location: 12, length: 10),
                      NSRange(location: 3, length: 2), NSRange(location: 30, length: 0), NSRange(location: 16, length: 2)]
        #expect(SourceViewerCoordinator.union(ranges) == [NSRange(location: 0, length: 5), NSRange(location: 10, length: 12)])
    }

    // MARK: - Model

    private static func repository(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return root
    }

    private static func model() throws -> (AppModel, UserDefaults, String) {
        let suite = "RadiologyTests." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suite))
        return (AppModel(preferences: preferences), preferences, suite)
    }

    private static func open(_ model: AppModel, _ path: String) async throws {
        model.openFile(path)
        try await waitUntil { model.source?.path == path && !model.isLoadingSource && model.syntax?.path == path }
    }

    @Test func explicitNavigationRevealsHiddenTestCodeAndBackStaysExact() async throws {
        let root = try Self.repository(["src/lib.rs": Self.rust])
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, preferences, suite) = try Self.model()
        defer { preferences.removePersistentDomain(forName: suite) }
        model.sourceFilters.hidesTests = true
        model.openRepository(root)
        try await Self.waitUntil { !model.isOpening }
        try await Self.open(model, "src/lib.rs")
        let buffer = try #require(model.source)
        let region = try #require(model.testCodePresentation?.regions.first)
        #expect(region.isHidden)
        #expect(!model.outlineSymbols.contains { $0.name == "detached_for_test" })
        #expect(model.outlineSymbols.contains { $0.name == "create_durable_agent" })

        // Depart from production line 8 to a byte inside the hidden helper.
        let departure = buffer.byteOffset(line: 8, column: 7)
        model.caretMoved(to: departure)
        model.updatePosition(path: "src/lib.rs", byteOffset: departure, line: 8)
        model.navigate(to: buffer.location(atByte: buffer.byteOffset(line: 5, column: 12)))
        #expect(model.revealedTestRegions == [region.id])
        #expect(model.testCodePresentation?.hiddenRegions.isEmpty == true)
        #expect(model.outlineSymbols.contains { $0.name == "detached_for_test" }, "revealed declarations return to the outline")
        model.goBack()
        #expect(model.navigationTarget == buffer.location(atByte: departure), "Back returns to the exact departure byte")
        #expect(model.revealedTestRegions == [region.id], "Back does not re-hide what navigation revealed")

        // The region's own control hides it again; Go to Line reveals it.
        model.toggleTestRegion(region.id)
        #expect(model.testCodePresentation?.hiddenRegions.count == 1)
        model.lineInput = 6
        model.goToLine()
        #expect(model.revealedTestRegions == [region.id])

        // Off hides nothing; on again re-hides every region. Neither moves
        // the caret, history, or source.
        let entries = model.history.entries
        let index = model.history.index
        let caret = model.currentCaretLocation(in: buffer)
        model.sourceFilters.hidesTests = false
        #expect(model.testCodePresentation == nil)
        #expect(model.outlineSymbols.count == model.syntax?.symbols.count)
        model.sourceFilters.hidesTests = true
        #expect(model.revealedTestRegions.isEmpty && model.testCodePresentation?.hiddenRegions.count == 1)
        #expect(model.history.entries == entries && model.history.index == index)
        #expect(model.currentCaretLocation(in: buffer) == caret)
        #expect(model.source?.data == buffer.data)
    }

    @Test func pendingRevealDefaultOpenIdentityAndTestDocuments() async throws {
        let top = "#[cfg(test)]\nmod t {\n    fn a() {}\n}\nfn prod() {}\n"
        let root = try Self.repository([
            "src/lib.rs": Self.rust,
            "src/copy.rs": Self.rust,
            "src/top.rs": top,
            "src/only_tests.rs": "#![cfg(test)]\nfn a() {}\n",
            "tests/integration.rs": top,
        ])
        defer { try? FileManager.default.removeItem(at: root) }
        let (model, preferences, suite) = try Self.model()
        defer { preferences.removePersistentDomain(forName: suite) }
        model.sourceFilters.hidesTests = true
        model.openRepository(root)
        try await Self.waitUntil { !model.isOpening }

        // A plain open at the top never reveals, even when a region starts at byte 0.
        try await Self.open(model, "src/top.rs")
        #expect(model.revealedTestRegions.isEmpty && model.testCodePresentation?.hiddenRegions.count == 1)

        // Cross-file navigation before parsing: revealed once syntax arrives.
        let target = try SourceBuffer(path: "src/lib.rs", data: Data(Self.rust.utf8)).byteOffset(line: 5, column: 8)
        model.navigate(to: SourceLocation(path: "src/lib.rs", byteOffset: target))
        try await Self.waitUntil { model.syntax?.path == "src/lib.rs" }
        let region = try #require(model.syntax?.testRegions.first)
        #expect(model.revealedTestRegions == [region.id])

        // Identical bytes at another path are another document: hidden again.
        try await Self.open(model, "src/copy.rs")
        #expect(model.revealedTestRegions.isEmpty && model.testCodePresentation?.hiddenRegions.count == 1)

        // Test documents opened explicitly are shown in full.
        try await Self.open(model, "tests/integration.rs")
        #expect(model.isTestDocument && model.syntax?.testRegions.isEmpty == false)
        #expect(model.testCodePresentation == nil)
        try await Self.open(model, "src/only_tests.rs")
        #expect(model.isTestDocument && model.syntax?.isTestOnlyDocument == true && model.testCodePresentation == nil)
    }
}
