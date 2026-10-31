import AppKit
import Testing
@testable import Radiology

@MainActor
struct ReaderFunctionFoldKeyTests {
    private func key(_ characters: String = "x", modifiers: NSEvent.ModifierFlags = [], repeating: Bool = false) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
                                     windowNumber: 0, context: nil, characters: characters,
                                     charactersIgnoringModifiers: characters, isARepeat: repeating, keyCode: 7))
    }

    private func harness() async throws -> (SourceBuffer, SyntaxSnapshot, ReaderTextView, SourceViewerCoordinator) {
        let source = """
        fn outer() {
            fn café() {
                let s = "🚀";
                work();
            }
            let callback = || {
                nested_work();
            };
            café();
        }

        fn sibling() {
            other_work();
        }
        """
        let buffer = try SourceBuffer(path: "a.rs", data: Data(source.utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let view = SourceCaretTests.reader(source)
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = view
        view.delegate = coordinator
        view.layoutManager?.delegate = coordinator
        _ = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: true)
        coordinator.applyFoldAttributes()
        view.byteForUTF16 = { buffer.byteOffset(forUTF16: $0) }
        view.onToggleEnclosingFunction = { [weak coordinator] byte in coordinator?.toggleFunction(at: byte) ?? false }
        return (buffer, syntax, view, coordinator)
    }

    @Test func xTogglesTheInnermostFunctionWithoutChangingSelectionOrSource() async throws {
        let (buffer, syntax, view, coordinator) = try await harness()
        let function = try #require(syntax.symbols.first { $0.name == "café" })
        let target = try #require(syntax.enclosingFunctionFold(at: function.selectionByteRange.lowerBound))
        let outer = try #require(syntax.symbols.first { $0.name == "outer" })
        let outerFold = try #require(syntax.enclosingFunctionFold(at: outer.selectionByteRange.lowerBound))
        let sibling = try #require(syntax.symbols.first { $0.name == "sibling" })
        let siblingFold = try #require(syntax.enclosingFunctionFold(at: sibling.selectionByteRange.lowerBound))
        coordinator.reveal(byteOffset: function.selectionByteRange.lowerBound)
        let caret = buffer.utf16Offset(forByte: function.selectionByteRange.lowerBound + 1)
        view.setSelectedRange(NSRange(location: caret, length: 0))
        let selection = view.selectedRange()
        var caretChanges = 0
        coordinator.onCaret = { _ in caretChanges += 1 }
        #expect(coordinator.isFolded(target.fold) && !coordinator.isFolded(outerFold.fold))
        view.keyDown(with: try key())
        #expect(!coordinator.isFolded(target.fold))
        let body = buffer.utf16Offset(forByte: buffer.byteOffset(line: 4, column: 10))
        #expect(view.insertionCaretRect(atCharacter: body) != nil)
        view.keyDown(with: try key())
        #expect(coordinator.isFolded(target.fold))
        #expect(view.insertionCaretRect(atCharacter: body) == nil)
        view.keyDown(with: try key(repeating: true))
        #expect(coordinator.isFolded(target.fold), "holding x does not alternate fold state")
        #expect(!coordinator.isFolded(outerFold.fold) && coordinator.isFolded(siblingFold.fold))
        #expect(view.selectedRange() == selection && view.string == buffer.text && caretChanges == 0)
        #expect(syntax.folds.filter { ![target.fold.id, outerFold.fold.id].contains($0.id) && $0.kind == "function" }.allSatisfy(coordinator.isFolded))
    }

    @Test func hiddenAncestorsOpenAndOutsideFunctionsDoesNothing() async throws {
        let (buffer, syntax, view, coordinator) = try await harness()
        let nested = try #require(syntax.symbols.first { $0.name == "café" })
        let nestedFold = try #require(syntax.enclosingFunctionFold(at: nested.selectionByteRange.lowerBound))
        let outer = try #require(syntax.symbols.first { $0.name == "outer" })
        let outerFold = try #require(syntax.enclosingFunctionFold(at: outer.selectionByteRange.lowerBound))
        let byte = buffer.byteOffset(line: 4, column: 10)
        coordinator.reveal(byteOffset: byte)
        coordinator.toggleFold(outerFold.fold)
        #expect(coordinator.isFolded(outerFold.fold) && !coordinator.isFolded(nestedFold.fold))
        view.setSelectedRange(NSRange(location: buffer.utf16Offset(forByte: byte), length: 0))
        view.keyDown(with: try key())
        #expect(!coordinator.isFolded(outerFold.fold) && !coordinator.isFolded(nestedFold.fold))
        #expect(view.insertionCaretRect(atCharacter: view.selectedRange().location) != nil)
        view.keyDown(with: try key())
        #expect(!coordinator.isFolded(outerFold.fold) && coordinator.isFolded(nestedFold.fold))
        #expect(!coordinator.toggleFunction(at: outer.byteRange.upperBound), "half-open boundary outside the declaration")
        #expect(!coordinator.toggleFunction(at: buffer.byteOffset(line: 11)), "between functions")
        coordinator.syntax = nil
        #expect(!coordinator.toggleFunction(at: byte), "no structure means no fold")
    }

    @Test func modifiedKeysAndEditableFieldsKeepTheirNativeHandling() throws {
        let buffer = try SourceBuffer(path: "unicode.rs", data: Data("let s = \"🚀\"; café();".utf8))
        let view = SourceCaretTests.reader(buffer.text)
        view.byteForUTF16 = { buffer.byteOffset(forUTF16: $0) }
        let byte = try #require(buffer.text.range(of: "café").map { buffer.text[..<$0.lowerBound].utf8.count + 2 })
        view.setSelectedRange(NSRange(location: buffer.utf16Offset(forByte: byte), length: 0))
        #expect(view.keyboardFunctionFoldByte(for: try key()) == byte)
        #expect(view.keyboardFunctionFoldByte(for: try key("X", modifiers: .capsLock)) == byte)
        for flags: NSEvent.ModifierFlags in [.command, .option, .control, .shift] {
            #expect(view.keyboardFunctionFoldByte(for: try key(modifiers: flags)) == nil)
        }
        #expect(view.keyboardFunctionFoldByte(for: try key("y")) == nil)
        view.isEditable = true
        #expect(view.keyboardFunctionFoldByte(for: try key()) == nil)
        var folded = false
        view.onToggleEnclosingFunction = { _ in folded = true; return true }
        view.keyDown(with: try key())
        #expect(!folded, "editable text does not invoke the source fold action")
    }

    @Test func parsedBodiesMatchAcrossLanguagesAndIgnoreParameterClosures() async throws {
        let examples: [(String, String)] = [
            ("a.swift", "func target() {\n    work()\n}\n"),
            ("a.go", "package p\nfunc target() {\n    work()\n}\n"),
            ("a.py", "def target():\n    work()\n    return 1\n"),
            ("a.js", "function target() {\n    work();\n}\n"),
            ("a.ts", "function target(): void {\n    work();\n}\n"),
            ("a.kt", "fun target(\n    factory: () -> Int = {\n        val value = 1\n        value\n    }\n): Int {\n    return 0\n}\n")
        ]
        for (path, source) in examples {
            let buffer = try SourceBuffer(path: path, data: Data(source.utf8))
            let syntax = try #require(try await SyntaxWorker().parse(buffer))
            let function = try #require(syntax.symbols.first { $0.name == "target" })
            let target = try #require(syntax.enclosingFunctionFold(at: function.selectionByteRange.lowerBound))
            #expect(target.fold.byteRange.upperBound == function.byteRange.upperBound)
            if path == "a.kt" {
                #expect(buffer.line(atByte: target.fold.byteRange.lowerBound) == 6, "fold the body, not the default lambda")
            }
        }
        let buffer = try SourceBuffer(path: "empty.rs", data: Data("trait P { fn target(&self); }\nfn short() {}\n".utf8))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        for declaration in syntax.symbols where SyntaxSnapshot.callableKinds.contains(declaration.kind) {
            #expect(syntax.enclosingFunctionFold(at: declaration.selectionByteRange.lowerBound) == nil)
        }
    }
}
