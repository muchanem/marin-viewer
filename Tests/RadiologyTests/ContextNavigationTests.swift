import AppKit
import Foundation
import Testing
@testable import Radiology

/// The Context inspector through `AppModel`: passive caret context never
/// navigates; explicit sidebar activations navigate and Back returns to the
/// exact caret, not to a viewport restoration point.
@MainActor
struct ContextNavigationTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        #expect(condition(), "timed out")
    }

    private func makeModel() throws -> (AppModel, URL, URL) {
        let root = try IndexingTests.temporaryRepository()
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fake = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(IndexingTests.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot.appending(path: "tools")))
        let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
        return (AppModel(preferences: preferences, semantics: SemanticModel(service: service)), root, cacheRoot)
    }

    private func open(_ path: String, in model: AppModel, root: URL) async throws -> SourceBuffer {
        if model.repository == nil {
            model.openRepository(root)
            try await waitUntil { !model.isOpening && model.semantics.status == .current }
        }
        model.openFile(path)
        try await waitUntil {
            model.source?.path == path && model.syntax?.path == path && model.semantics.documentSemantics?.path == path
        }
        return try #require(model.source)
    }

    private struct NavigationState: Equatable {
        let path: String?
        let target: Radiology.SourceLocation?
        let revision: Int
        let selectsText: Bool
        let history: [Radiology.SourceLocation]
        let historyIndex: Int
        let highlightRevision: Int
        let positions: [String: Radiology.SourceLocation]
        @MainActor init(_ model: AppModel) {
            path = model.source?.path
            target = model.navigationTarget
            revision = model.navigationRevision
            selectsText = model.navigationSelectsText
            history = model.history.entries
            historyIndex = model.history.index
            highlightRevision = model.jumpHighlightRevision
            positions = model.positions
        }
    }

    @Test func passiveCaretMovementOnlyUpdatesContext() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let lib = try await open("src/lib.rs", in: model, root: root)
        let before = NavigationState(model)
        // Through `Circle` (cross-file preview), `items`, `area`, whitespace, and back.
        for (line, column) in [(5, 27), (5, 29), (5, 19), (8, 21), (6, 0), (7, 9), (5, 30)] {
            model.caretMoved(to: lib.byteOffset(line: line, column: column))
        }
        #expect(model.context.declaration?.declaration.name == "total_area")
        #expect(model.context.underCaret?.target.displayName == "Circle")
        try await waitUntil { if case .loaded = model.context.preview { true } else { false } }
        try await waitUntil { if case .loaded = model.context.references { true } else { false } }
        // Disclosure only reveals detail.
        model.context.isDeclarationExpanded = true
        model.context.isDefinitionExpanded = true
        if case .loaded(let results) = model.context.references, let hit = results.groups.first?.hits.first {
            model.context.toggleReference(hit.id)
            model.context.selectedReferenceID = hit.id
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(NavigationState(model) == before, "context, selection, disclosure, and async previews never navigate, scroll, or record history")
        #expect(model.currentCaretLocation == Radiology.SourceLocation(path: "src/lib.rs", byteOffset: lib.byteOffset(line: 5, column: 30)))
    }

    @Test func scrollingDoesNotChangeTheEnclosingDeclaration() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let shapes = try await open("src/shapes.rs", in: model, root: root)
        model.caretMoved(to: shapes.byteOffset(line: 8, column: 12))
        #expect(model.context.declaration?.declaration.name == "area")
        // The viewer reports viewport positions through updatePosition only.
        model.updatePosition(path: "src/shapes.rs", byteOffset: shapes.byteOffset(line: 1), line: 1)
        model.refreshContext()
        #expect(model.context.declaration?.declaration.name == "area")
        #expect(model.currentCaretLocation?.byteOffset == shapes.byteOffset(line: 8, column: 12))
    }

    @Test func referencesPreviewWithoutNavigatingAndBackReturnsToTheCaret() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let shapes = try await open("src/shapes.rs", in: model, root: root)
        let caret = Radiology.SourceLocation(path: "src/shapes.rs", byteOffset: shapes.byteOffset(line: 8, column: 12))
        model.caretMoved(to: caret.byteOffset)
        // The reader then scrolls: the restoration point moves, the caret does not.
        model.updatePosition(path: "src/shapes.rs", byteOffset: shapes.byteOffset(line: 1), line: 1)
        try await waitUntil { if case .loaded = model.context.references { true } else { false } }
        guard case .loaded(let results) = model.context.references else { return }
        let call = try #require(results.groups.first { $0.path == "src/lib.rs" }?.hits.first)
        let definition = try #require(results.groups.first { $0.path == "src/shapes.rs" }?.hits.first)
        let before = NavigationState(model)

        // Selecting rows (Up/Down) is preview only.
        model.context.selectedReferenceID = definition.id
        model.context.selectedReferenceID = call.id
        #expect(model.context.selectedReference?.context.contains { $0.number == 8 && $0.text.contains("item.area()") } == true)
        #expect(NavigationState(model) == before)

        // Return commits.
        model.commitSelectedReference()
        try await waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget == call.location)
        #expect(model.jumpHighlightTarget == call.location)
        #expect(model.currentCaretLocation == call.location)

        // ⌘[ returns to the exact caret, not the scrolled-to line 1.
        model.goBack()
        try await waitUntil { model.source?.path == "src/shapes.rs" }
        #expect(model.navigationTarget == caret)
        #expect(model.currentCaretLocation == caret)
        model.goForward()
        try await waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget == call.location)
    }

    @Test func nativeListActionsCommitTheNamedRowNotTheStoredSelection() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let shapes = try await open("src/shapes.rs", in: model, root: root)
        let caret = Radiology.SourceLocation(path: "src/shapes.rs", byteOffset: shapes.byteOffset(line: 8, column: 12))
        model.caretMoved(to: caret.byteOffset)
        try await waitUntil { if case .loaded = model.context.references { true } else { false } }
        guard case .loaded(let results) = model.context.references else { return }
        let call = try #require(results.groups.first { $0.path == "src/lib.rs" }?.hits.first)
        let definition = try #require(results.groups.first { $0.path == "src/shapes.rs" }?.hits.first)
        // Keyboard selection is on the definition; a double-click/context menu names the call.
        model.context.selectedReferenceID = definition.id
        model.commitReference(id: call.id)
        try await waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget == call.location)
        model.goBack()
        try await waitUntil { model.source?.path == "src/shapes.rs" }
        #expect(model.navigationTarget == caret)
        // An ID from a superseded result list does nothing.
        let revision = model.navigationRevision
        model.commitReference(id: "src/elsewhere.rs:0")
        #expect(model.navigationRevision == revision)
    }

    @Test func callerTreeNavigationReturnsToExactDepartureCaret() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let shapes = try await open("src/shapes.rs", in: model, root: root)
        let caret = Radiology.SourceLocation(path: shapes.path, byteOffset: shapes.byteOffset(line: 8, column: 12))
        model.caretMoved(to: caret.byteOffset)
        model.updatePosition(path: shapes.path, byteOffset: 0, line: 1)
        try await waitUntil { if case .loaded = model.context.references { true } else { false } }
        guard case .loaded(let results) = model.context.references else { return }
        let hit = try #require(results.groups.first { $0.path == "src/lib.rs" }?.hits.first)
        let before = NavigationState(model)
        model.context.setReference(hit.id, expanded: true)
        try await waitUntil { if case .loaded = model.context.referenceCallTrees[hit.id] { true } else { false } }
        #expect(NavigationState(model) == before)
        guard case .loaded(let tree) = model.context.referenceCallTrees[hit.id] else { return }
        let caller = try #require(tree.callers.first)
        model.commitCaller(caller)
        try await waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.currentCaretLocation == caller.location)
        model.goBack()
        try await waitUntil { model.source?.path == shapes.path }
        #expect(model.currentCaretLocation == caret)
    }

    @Test func sidebarDefinitionActivationsRecordTheCaretNotTheViewport() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let lib = try await open("src/lib.rs", in: model, root: root)

        // Under-caret definition (button / Return): `item.area()` → shapes.rs.
        let areaCall = Radiology.SourceLocation(path: "src/lib.rs", byteOffset: lib.byteOffset(line: 8, column: 21))
        model.caretMoved(to: areaCall.byteOffset)
        model.updatePosition(path: "src/lib.rs", byteOffset: 0, line: 1)
        #expect(model.context.underCaret?.destination?.path == "src/shapes.rs")
        model.goToUnderCaretDefinition()
        try await waitUntil { model.source?.path == "src/shapes.rs" }
        let shapes = try #require(model.source)
        #expect(model.navigationTarget == Radiology.SourceLocation(path: "src/shapes.rs", byteOffset: shapes.byteOffset(line: 7, column: 11)))
        model.goBack()
        try await waitUntil { model.source?.path == "src/lib.rs" }
        #expect(model.navigationTarget == areaCall)

        // Enclosing declaration button: same file, scrolled away after placing the caret.
        try await waitUntil { model.syntax?.path == "src/lib.rs" && model.semantics.documentSemantics?.path == "src/lib.rs" }
        let inBody = Radiology.SourceLocation(path: "src/lib.rs", byteOffset: lib.byteOffset(line: 7, column: 10))
        model.caretMoved(to: inBody.byteOffset)
        model.updatePosition(path: "src/lib.rs", byteOffset: lib.byteOffset(line: 10), line: 10)
        #expect(model.context.declaration?.declaration.name == "total_area")
        model.revealDeclaration()
        let name = Radiology.SourceLocation(path: "src/lib.rs", byteOffset: lib.byteOffset(line: 5, column: 7))
        #expect(model.navigationTarget == name)
        #expect(model.history.current == name)
        model.goBack()
        #expect(model.navigationTarget == inBody, "Back restores the caret inside the body, not line 10")
    }

    @Test func fileAndRepositoryChangesResetContext() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        let lib = try await open("src/lib.rs", in: model, root: root)
        model.caretMoved(to: lib.byteOffset(line: 5, column: 28))
        #expect(model.context.underCaret?.identity.path == "src/lib.rs")
        model.openFile("src/shapes.rs")
        #expect(model.context.underCaret == nil, "a file change clears stale identities immediately")
        #expect(model.context.declaration == nil)
        try await waitUntil { model.semantics.documentSemantics?.path == "src/shapes.rs" && model.syntax?.path == "src/shapes.rs" }
        #expect(model.context.declaration?.declaration.name == "Circle", "the restored caret at byte 0 is inside `pub struct Circle`")

        let plain = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        try Data("fn only() {\n    let x = 1;\n}\n".utf8).write(to: plain.appending(path: "a.rs"))
        model.openRepository(plain)
        #expect(model.context.declaration == nil && model.context.underCaret == nil)
        #expect(model.context.references == .unavailable)
        try await waitUntil { !model.isOpening }
        model.openFile("a.rs")
        try await waitUntil { model.syntax?.path == "a.rs" }
        model.caretMoved(to: 18)
        // Structure still works with no semantic index; nothing semantic is invented.
        #expect(model.context.declaration?.declaration.name == "only")
        #expect(model.context.declaration?.link == DeclarationContext.Link.none)
        #expect(model.context.underCaret == nil)
        #expect(model.context.references == .unavailable)
        #expect(!model.referencesUnavailableReason.isEmpty)
    }

    /// tkos README.md shape: an unindexed file in a repository whose index is
    /// usable must say the *file* is not indexed, not that there is no index.
    @Test func unindexedFileInAnIndexedRepositoryIsLabelledByFileCoverage() async throws {
        let (model, root, cacheRoot) = try makeModel()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cacheRoot) }
        _ = try await open("src/lib.rs", in: model, root: root)
        #expect(model.semanticAvailability == .available)
        #expect(model.underCaretFallbackDetail == nil)

        model.openFile("Cargo.toml")
        try await waitUntil { model.source?.path == "Cargo.toml" && !model.isLoadingSource }
        model.caretMoved(to: 1)
        #expect(model.semantics.hasIndex)
        #expect(model.semanticAvailability == .fileNotIndexed)
        #expect(model.underCaretFallbackDetail == "File not indexed")
        #expect(model.referencesUnavailableReason.contains("does not cover this file"))
        #expect(model.context.underCaret == nil && model.context.declaration == nil)

        // A repository with no index at all is described as such.
        let plain = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: plain) }
        try Data("fn only() {}\n".utf8).write(to: plain.appending(path: "a.rs"))
        model.openRepository(plain)
        try await waitUntil { !model.isOpening }
        model.openFile("a.rs")
        try await waitUntil { model.source?.path == "a.rs" }
        #expect(model.underCaretFallbackDetail == "No semantic index")
        guard case .repositoryNotIndexed = model.semanticAvailability else {
            Issue.record("expected repositoryNotIndexed, got \(model.semanticAvailability)")
            return
        }
    }

    /// AppKit boundary: selection changes report the caret; scrolling reports
    /// only a restoration position.
    @Test func viewerReportsCaretOnlyForSelectionChanges() throws {
        let buffer = try SourceBuffer(path: "a.rs", data: Data((0..<200).map { "fn f\($0)() { let 🚀 = \($0); }" }.joined(separator: "\n").utf8))
        let scroll = SourceScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let text = ReaderTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        text.isVerticallyResizable = true
        text.string = buffer.text
        scroll.documentView = text
        let coordinator = SourceViewerCoordinator()
        coordinator.textView = text
        coordinator.scrollView = scroll
        coordinator.buffer = buffer
        text.delegate = coordinator
        var carets: [Int] = []
        var positions: [Int] = []
        coordinator.onCaret = { carets.append($0) }
        coordinator.onPosition = { byte, _ in positions.append(byte) }

        let line = buffer.text.components(separatedBy: "\n")[3]
        let utf16 = buffer.utf16LineStarts[3] + (line as NSString).range(of: "= 3").location
        text.setSelectedRange(NSRange(location: utf16, length: 0))
        #expect(carets == [buffer.byteOffset(forUTF16: utf16)])
        #expect(carets.first.map { buffer.data[$0] } == UInt8(ascii: "="), "UTF-16 after an emoji maps to the right byte")

        text.scroll(NSPoint(x: 0, y: 900))
        coordinator.didScroll(Notification(name: NSView.boundsDidChangeNotification))
        #expect(carets.count == 1, "scrolling never moves the caret")
        #expect(!positions.isEmpty)
    }
}
