import AppKit
import Foundation
import Testing
@testable import Radiology

@MainActor
struct ReviewFoldDefaultsTests {
    static let rust = """
    fn outer() {
        fn nested(
            arg: i32,
        ) -> i32 {
            arg + 1
        }
        let a = || {
            1
        };
        let b = || {
            2
        };
        nested(a()) + b();
    }
    fn quiet() -> i32 {
        3
    }
    """

    func harness(_ text: String = Self.rust) async throws -> (SourceViewerCoordinator, SourceBuffer, SyntaxSnapshot, ReaderTextView) {
        var buffer = try SourceBuffer(path: "a.rs", data: Data(text.utf8))
        buffer.revision = .after
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let view = SourceCaretTests.reader(text)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = view
        coordinator.reviewIdentity = "review"
        view.layoutManager?.delegate = coordinator
        return (coordinator, buffer, syntax, view)
    }

    func input(_ buffer: SourceBuffer, line: Int, count: Int = 1, review: String = "review") -> ReviewFoldInput {
        ReviewFoldInput(reviewID: review, path: buffer.path, revision: buffer.revision!, sourceIdentity: SourceContentIdentity(buffer.data),
                        changes: FileLineChanges(hunks: [.init(beforeStart: line, beforeCount: count, afterStart: line, afterCount: count)], isBinary: false))
    }

    func function(_ name: String, _ syntax: SyntaxSnapshot) throws -> SourceFold {
        let declaration = try #require(syntax.symbols.first { $0.name == name })
        return try #require(syntax.folds.first { $0.kind == "function" && $0.byteRange.upperBound == declaration.byteRange.upperBound })
    }

    @Test func signatureChangeOpensOwnBodyAndAncestorsButNotSiblingClosures() async throws {
        let (coordinator, buffer, syntax, view) = try await harness()
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        let nested = try function("nested", syntax)
        let outer = try function("outer", syntax)
        let quiet = try function("quiet", syntax)
        let identity = SourceContentIdentity(buffer.data)
        let selected = input(buffer, line: 3).foldsToExpand(in: syntax, buffer: buffer)
        #expect(selected.contains(nested.id) && selected.contains(outer.id))
        let closureFolds = syntax.folds.filter { $0.kind == "function" && ![nested.id, outer.id, quiet.id].contains($0.id) }
        #expect(closureFolds.count == 2 && closureFolds.allSatisfy { !selected.contains($0.id) })
        let closureChange = input(buffer, line: 8).foldsToExpand(in: syntax, buffer: buffer)
        #expect(closureFolds.filter { closureChange.contains($0.id) }.count == 1)
        #expect(closureChange.contains(outer.id) && !closureChange.contains(nested.id))
        let added = ReviewFoldInput(reviewID: "review", path: buffer.path, revision: .after, sourceIdentity: identity,
            changes: FileLineChanges(hunks: [.init(beforeStart: 14, beforeCount: 0, afterStart: 15, afterCount: 3)], isBinary: false))
        #expect(added.foldsToExpand(in: syntax, buffer: buffer).contains(quiet.id))
        view.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(coordinator.applyInitialReviewFolds(input(buffer, line: 3), sourceIdentity: identity))
        coordinator.applyFoldAttributes()
        #expect(!coordinator.isFolded(nested) && !coordinator.isFolded(outer) && coordinator.isFolded(quiet))
        #expect(closureFolds.allSatisfy(coordinator.isFolded))
        #expect(view.selectedRange() == NSRange(location: 2, length: 0) && view.string == Self.rust)
    }

    @Test func attachedAttributeAndDecoratorOnlyEditsOwnTheFunctionNotItsClosures() async throws {
        let rust = """
        #[cfg(target_os = "android")]
        fn marked() {
            let a = || {
                1
            };
            let b = || {
                2
            };
            a() + b();
        }
        fn quiet() {
            3;
        }
        """
        let (_, buffer, syntax, _) = try await harness(rust)
        let marked = try function("marked", syntax)
        let selected = input(buffer, line: 1).foldsToExpand(in: syntax, buffer: buffer)
        #expect(selected.contains(marked.id))
        #expect(syntax.folds.filter { $0.kind == "function" && selected.contains($0.id) }.count == 1)
        let python = "@trace\ndef marked():\n    first = 1\n    second = 2\n\ndef quiet():\n    first = 3\n    second = 4"
        var pyBuffer = try SourceBuffer(path: "a.py", data: Data(python.utf8)); pyBuffer.revision = .after
        let pySyntax = try #require(try await SyntaxWorker().parse(pyBuffer))
        let pySelected = input(pyBuffer, line: 1).foldsToExpand(in: pySyntax, buffer: pyBuffer)
        #expect(pySelected.contains(try function("marked", pySyntax).id))
        #expect(!pySelected.contains(try function("quiet", pySyntax).id))
    }

    @Test func asynchronousOrdersAndManualChoicesApplyOnlyOnce() async throws {
        let (coordinator, buffer, syntax, _) = try await harness()
        let identity = SourceContentIdentity(buffer.data)
        _ = coordinator.updateSyntax(nil, buffer: buffer, resetFolds: true)
        #expect(!coordinator.applyInitialReviewFolds(input(buffer, line: 5), sourceIdentity: identity))
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: false)
        #expect(coordinator.applyInitialReviewFolds(input(buffer, line: 5), sourceIdentity: identity))
        let nested = try function("nested", syntax)
        coordinator.toggleFold(nested)
        #expect(!coordinator.applyInitialReviewFolds(input(buffer, line: 5), sourceIdentity: identity) && coordinator.isFolded(nested))

        let (late, other, parsed, _) = try await harness()
        _ = late.updateSyntax(parsed, buffer: other, resetFolds: true)
        #expect(!late.applyInitialReviewFolds(nil, sourceIdentity: identity))
        let quiet = try function("quiet", parsed)
        late.toggleFold(quiet) // unrelated manual expansion survives late diff
        late.toggleFold(nested); late.toggleFold(nested) // explicit recollapse while diff pending
        _ = late.applyInitialReviewFolds(input(other, line: 5), sourceIdentity: identity)
        #expect(late.isFolded(nested) && !late.isFolded(quiet))
    }

    @Test func bulkCommandBaselineDoesNotReplayOldCommandsButNewCommandsOverride() async throws {
        let (coordinator, buffer, syntax, _) = try await harness()
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        #expect(!coordinator.consumeFoldCommands(definitions: 7, functions: 9))
        _ = coordinator.applyInitialReviewFolds(input(buffer, line: 5), sourceIdentity: SourceContentIdentity(buffer.data))
        let nested = try function("nested", syntax)
        #expect(!coordinator.isFolded(nested))
        #expect(coordinator.consumeFoldCommands(definitions: 7, functions: 10) && coordinator.isFolded(nested))
        var before = buffer; before.revision = .before
        _ = coordinator.updateSyntax(syntax, buffer: before, resetFolds: true)
        #expect(!coordinator.consumeFoldCommands(definitions: 7, functions: 10))
        #expect(coordinator.applyInitialReviewFolds(input(before, line: 5), sourceIdentity: SourceContentIdentity(before.data)))
        #expect(!coordinator.isFolded(nested))
        #expect(coordinator.consumeFoldCommands(definitions: 8, functions: 10) && coordinator.isFolded(nested))

        let (pending, same, parsed, _) = try await harness()
        _ = pending.updateSyntax(parsed, buffer: same, resetFolds: true)
        _ = pending.consumeFoldCommands(definitions: 0, functions: 0)
        _ = pending.consumeFoldCommands(definitions: 0, functions: 1)
        #expect(!pending.applyInitialReviewFolds(input(same, line: 5), sourceIdentity: SourceContentIdentity(same.data)))
        #expect(pending.isFolded(nested))
    }

    @Test func identityAndRevisionGuardsAndLocalDefaults() async throws {
        let (coordinator, buffer, syntax, _) = try await harness()
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        let nested = try function("nested", syntax)
        #expect(coordinator.isFolded(nested))
        #expect(!coordinator.applyInitialReviewFolds(nil, sourceIdentity: SourceContentIdentity(buffer.data)))
        #expect(!coordinator.applyInitialReviewFolds(input(buffer, line: 5, review: "old"), sourceIdentity: SourceContentIdentity(buffer.data)))
        #expect(!coordinator.applyInitialReviewFolds(input(buffer, line: 5), sourceIdentity: SourceContentIdentity(Data("stale".utf8))))
        var before = buffer; before.revision = .before
        #expect(!coordinator.applyInitialReviewFolds(input(before, line: 5), sourceIdentity: SourceContentIdentity(buffer.data)))
        #expect(coordinator.applyInitialReviewFolds(input(buffer, line: 5), sourceIdentity: SourceContentIdentity(buffer.data)))
        var copy = try SourceBuffer(path: "copy.rs", data: buffer.data); copy.revision = .after
        _ = coordinator.updateSyntax(nil, buffer: copy, resetFolds: true)
        #expect(!coordinator.applyInitialReviewFolds(input(buffer, line: 5), sourceIdentity: SourceContentIdentity(copy.data)))
    }

    @Test func emptySidesExpandContainingBlocksButNotClosedEOFNeighborsOrTestRegions() async throws {
        let text = "fn changed() {\n    #[cfg(test)]\n    fn helper() { 1; }\n    production();\n}\nfn quiet() {\n    2;\n}"
        let (coordinator, buffer, syntax, view) = try await harness(text)
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        let changes = FileLineChanges(hunks: [.init(beforeStart: 4, beforeCount: 1, afterStart: 3, afterCount: 0)], isBinary: false)
        let data = ReviewFoldInput(reviewID: "review", path: buffer.path, revision: .after, sourceIdentity: SourceContentIdentity(buffer.data), changes: changes)
        let presentation = TestCodePresentation(regions: syntax.testRegions, revealed: [], buffer: buffer, sourceIdentity: data.sourceIdentity)
        _ = coordinator.setTestPresentation(presentation)
        #expect(coordinator.applyInitialReviewFolds(data, sourceIdentity: data.sourceIdentity))
        coordinator.applyFoldAttributes()
        #expect(!coordinator.isFolded(try function("changed", syntax)))
        #expect(coordinator.testPresentation == presentation && view.testRegionLabels.first?.isHidden == true)
        let eof = ReviewFoldInput(reviewID: "review", path: buffer.path, revision: .after, sourceIdentity: data.sourceIdentity,
            changes: FileLineChanges(hunks: [.init(beforeStart: 9, beforeCount: 4, afterStart: 8, afterCount: 0)], isBinary: false))
        #expect(eof.foldsToExpand(in: syntax, buffer: buffer).isEmpty, "deletion after a closed final function does not implicate it")
        let removed = ReviewFoldInput(reviewID: "review", path: buffer.path, revision: .before, sourceIdentity: data.sourceIdentity,
            changes: FileLineChanges(hunks: [.init(beforeStart: 6, beforeCount: 3, afterStart: 6, afterCount: 0)], isBinary: false))
        #expect(removed.foldsToExpand(in: syntax, buffer: buffer).contains(try function("quiet", syntax).id))
        var python = try SourceBuffer(path: "a.py", data: Data("def work():\n    first = 1\n    second = 2".utf8))
        python.revision = .after
        let pySyntax = try #require(try await SyntaxWorker().parse(python))
        let pyEOF = ReviewFoldInput(reviewID: "review", path: python.path, revision: .after,
            sourceIdentity: SourceContentIdentity(python.data),
            changes: FileLineChanges(hunks: [.init(beforeStart: 4, beforeCount: 1, afterStart: 3, afterCount: 0)], isBinary: false))
        #expect(!pyEOF.foldsToExpand(in: pySyntax, buffer: python).isEmpty, "unterminated indentation body owns its EOF point")
    }
    @Test func lateExpansionPreservesViewportAndNewerExplicitJumpWins() async throws {
        let text = Self.rust + "\n" + (1...50).map { "// tail \($0)" }.joined(separator: "\n")
        let (coordinator, buffer, syntax, view) = try await harness(text)
        let scroll = SourceScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        scroll.documentView = view
        coordinator.scrollView = scroll
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        coordinator.applyFoldAttributes()
        view.setSelectedRange(NSRange(location: 2, length: 0))
        scroll.pendingLocation = buffer.utf16Offset(forByte: buffer.byteOffset(line: 30))
        scroll.layout()
        let top = try #require(coordinator.visibleTopCharacter())
        var positions = 0
        var carets = 0
        var reportedPosition: (byte: Int, caretLine: Int)?
        coordinator.onPosition = { byte, line in positions += 1; reportedPosition = (byte, line) }
        coordinator.onCaret = { _ in carets += 1 }
        view.delegate = coordinator
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(coordinator, selector: #selector(SourceViewerCoordinator.didScroll),
                                               name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        defer { NotificationCenter.default.removeObserver(coordinator) }
        #expect(coordinator.applyInitialReviewFolds(input(buffer, line: 5), sourceIdentity: SourceContentIdentity(buffer.data)))
        coordinator.applyFoldAttributes()
        coordinator.programmaticPositionByte = 0 // obsolete initial navigation never consumed
        coordinator.preserveViewport(atCharacter: top)
        scroll.layout()
        #expect(coordinator.visibleTopCharacter() == top)
        #expect(view.selectedRange().location == 2)
        #expect(positions == 0 && carets == 0, "late layout cannot publish a navigation/caret departure")
        // A newer navigation must clear the old restore before layout, not
        // silently discard the requested jump in favor of that old source row.
        coordinator.preserveViewport(atCharacter: top)
        let jump = buffer.utf16Offset(forByte: buffer.byteOffset(line: 45))
        scroll.pendingLocation = jump
        scroll.layout()
        #expect(scroll.pendingViewportCharacter == nil && scroll.pendingLocation == nil)
        let glyph = view.layoutManager!.glyphIndexForCharacter(at: jump)
        let expectedY = view.layoutManager!.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY
        #expect(scroll.contentView.bounds.minY == expectedY)
        #expect(coordinator.visibleTopCharacter() != top)
        #expect(view.selectedRange().location == 2)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: scroll.contentView.bounds.minY + 25))
        let position = try #require(reportedPosition)
        let layout = view.layoutManager!
        let glyphAtTop = layout.glyphIndex(for: NSPoint(x: 0, y: max(0, view.visibleRect.minY)), in: view.textContainer!)
        let actualTop = buffer.byteOffset(forUTF16: layout.characterIndexForGlyph(at: glyphAtTop))
        #expect(position.byte == actualTop && position.byte != 0)
        #expect(position.caretLine == 1 && carets == 0, "user scroll changes viewport position, not caret line")
    }

}
