import AppKit
import Foundation
import Testing
@testable import Radiology

/// Return/Enter in the focused source reader follows the semantic symbol at
/// the caret or native selection, through the real `keyDown` route.
@MainActor
struct ReaderReturnKeyTests {
    static func key(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let characters = code == ReaderTextView.keypadEnterKeyCode ? "\u{3}" : "\r"
        return try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                             windowNumber: 0, context: nil, characters: characters,
                                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
    }

    static func target(_ range: Range<Int>, definitions: Int, onDefinition: Bool = false) -> SemanticTarget {
        let position = SemanticPosition(path: "other.rs", range: SCIPRange(startLine: 0, startCharacter: 0, endLine: 0, endCharacter: 1), encoding: .utf8)
        return SemanticTarget(symbol: SemanticSymbolID(symbol: "scip cargo t 1 f().", document: "a.rs"), displayName: "f",
                              kind: SemanticSymbolKind(rawValue: 17), byteRange: range, isOnDefinition: onDefinition,
                              definitions: Array(repeating: position, count: definitions), referenceCount: 1)
    }

    /// Emoji and an accented identifier precede the call, so UTF-16 and UTF-8
    /// offsets differ; only bytes inside `appel` (and its end) resolve.
    @Test func returnFollowsTheSemanticCallAtTheCaretOrSelection() throws {
        let line = "let 🚀 = \"é\"; appel(x); extern_call(); défini();"
        let buffer = try SourceBuffer(path: "a.rs", data: Data(line.utf8))
        func bytes(of needle: String) -> Range<Int> {
            let range = line.range(of: needle)!
            let lower = line.utf8.distance(from: line.startIndex, to: range.lowerBound)
            return lower..<(lower + needle.utf8.count)
        }
        let call = bytes(of: "appel")
        let external = bytes(of: "extern_call")
        let definitionHere = bytes(of: "défini")
        let text = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 100))
        text.isEditable = false
        text.string = buffer.text
        text.byteForUTF16 = { buffer.byteOffset(forUTF16: $0) }
        text.semanticTarget = { byte in
            if call.contains(byte) { return Self.target(call, definitions: 1) }
            if external.contains(byte) { return Self.target(external, definitions: 0) }
            if definitionHere.contains(byte) { return Self.target(definitionHere, definitions: 0, onDefinition: true) }
            return nil
        }
        var routes: [[Int]] = []
        text.onKeyboardGoToDefinition = { routes.append([$0, $1]) }
        func caret(atByte byte: Int, length: Int = 0) {
            let start = buffer.utf16Offset(forByte: byte)
            text.setSelectedRange(NSRange(location: start, length: buffer.utf16Offset(forByte: byte + length) - start))
        }

        // Caret inside the call, after the emoji: Return and keypad Enter.
        caret(atByte: call.lowerBound + 2)
        text.keyDown(with: try Self.key(ReaderTextView.returnKeyCode))
        text.keyDown(with: try Self.key(ReaderTextView.keypadEnterKeyCode))
        #expect(routes == [[call.lowerBound + 2, call.lowerBound + 2], [call.lowerBound + 2, call.lowerBound + 2]])

        // Caret just past the identifier (arrowed to its end): target the
        // occurrence, but depart from the caret itself.
        routes = []
        caret(atByte: call.upperBound)
        text.keyDown(with: try Self.key(ReaderTextView.returnKeyCode))
        #expect(routes == [[call.upperBound - 1, call.upperBound]])

        // Word selection (double-click) of exactly the call.
        routes = []
        caret(atByte: call.lowerBound, length: call.count)
        text.keyDown(with: try Self.key(ReaderTextView.returnKeyCode))
        #expect(routes == [[call.lowerBound, call.lowerBound]])
        #expect(text.selectedRange().length == "appel".utf16.count, "the native selection is untouched")

        // Not handled: a selection extending beyond the occurrence, modified
        // Return, an external symbol, the definition itself, whitespace/emoji.
        routes = []
        caret(atByte: call.lowerBound, length: call.count + 2)
        text.keyDown(with: try Self.key(ReaderTextView.returnKeyCode))
        caret(atByte: call.lowerBound + 1)
        for modifier: NSEvent.ModifierFlags in [.shift, .command, .option, .control] {
            #expect(text.keyboardDefinitionRoute(for: try Self.key(ReaderTextView.returnKeyCode, modifier)) == nil)
        }
        for byte in [external.lowerBound + 3, definitionHere.lowerBound + 1, bytes(of: "🚀").lowerBound, 0] {
            caret(atByte: byte)
            text.keyDown(with: try Self.key(ReaderTextView.returnKeyCode))
        }
        #expect(routes.isEmpty, "no target, external, on-definition, and over-wide selections fall through")
        // Other keys are never routed.
        caret(atByte: call.lowerBound + 1)
        #expect(text.keyboardDefinitionRoute(for: try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))) == nil)
    }

    /// The whole route against the real fixture index: the reader's Return
    /// reaches AppModel's semantic Go to Definition, and ⌘[ restores the exact
    /// departure caret even after the reader scrolled.
    @Test func returnNavigatesAndBackRestoresTheExactCaretAfterScrolling() async throws {
        let root = try IndexingTests.temporaryRepository()
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let fake = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(IndexingTests.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot.appending(path: "tools")))
        let model = AppModel(preferences: try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString)),
                             semantics: SemanticModel(service: service))
        model.openRepository(root)
        try await IndexingTests.waitUntil { !model.isOpening && model.semantics.status == .current }
        model.openFile("src/lib.rs")
        try await IndexingTests.waitUntil { model.semantics.documentSemantics?.path == "src/lib.rs" }
        let lib = try #require(model.source)

        // Wire the reader exactly as SourceViewer does.
        let text = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        text.isEditable = false
        text.string = lib.text
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.buffer = lib
        coordinator.onCaret = { model.caretMoved(to: $0) }
        coordinator.onPosition = { model.updatePosition(path: "src/lib.rs", byteOffset: $0, line: $1) }
        text.delegate = coordinator
        text.byteForUTF16 = { lib.byteOffset(forUTF16: $0) }
        text.semanticTarget = { model.semantics.target(at: $0) }
        text.onKeyboardGoToDefinition = { model.goToDefinition(at: $0, departingFrom: $1) }

        // Caret in the middle of `area` in `item.area()` (line 8), then a passive scroll.
        let caret = Radiology.SourceLocation(path: "src/lib.rs", byteOffset: lib.byteOffset(line: 8, column: 22))
        text.setSelectedRange(NSRange(location: lib.utf16Offset(forByte: caret.byteOffset), length: 0))
        #expect(model.currentCaretLocation == caret)
        model.updatePosition(path: "src/lib.rs", byteOffset: 0, line: 1)
        let revision = model.navigationRevision

        text.keyDown(with: try Self.key(ReaderTextView.returnKeyCode))
        try await IndexingTests.waitUntil { model.source?.path == "src/shapes.rs" }
        let shapes = try #require(model.source)
        #expect(model.navigationRevision > revision)
        #expect(model.navigationTarget == Radiology.SourceLocation(path: "src/shapes.rs", byteOffset: shapes.byteOffset(line: 7, column: 11)))
        #expect(model.jumpHighlightTarget == model.navigationTarget)

        model.goBack()
        try await IndexingTests.waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget == caret, "Back restores the exact caret, not the scrolled-to top")
        model.goForward()
        try await IndexingTests.waitUntil { model.source?.path == "src/shapes.rs" }
        #expect(model.navigationTarget?.byteOffset == shapes.byteOffset(line: 7, column: 11))

        // Return on the definition itself (no other definition) does not navigate.
        model.goBack()
        try await IndexingTests.waitUntil { model.source?.path == "src/lib.rs" && model.semantics.documentSemantics?.path == "src/lib.rs" }
        let onDefinition = lib.byteOffset(line: 5, column: 9)   // `total_area` in its own signature
        text.setSelectedRange(NSRange(location: lib.utf16Offset(forByte: onDefinition), length: 0))
        let before = model.navigationRevision
        text.keyDown(with: try Self.key(ReaderTextView.returnKeyCode))
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.navigationRevision == before)
        #expect(model.source?.path == "src/lib.rs")
    }
}
