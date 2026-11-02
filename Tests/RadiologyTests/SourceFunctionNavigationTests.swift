import SwiftUI
import Testing
@testable import Radiology

@Suite(.serialized) @MainActor
struct SourceFunctionNavigationTests {
    private func reader(in view: NSView) -> ReaderTextView? {
        if let reader = view as? ReaderTextView { return reader }
        for child in view.subviews { if let reader = reader(in: child) { return reader } }
        return nil
    }

    private func coordinator(in view: NSView) -> SourceViewerCoordinator? {
        reader(in: view)?.delegate as? SourceViewerCoordinator
    }

    private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(condition(), Comment(rawValue: message))
    }

    @Test func codePathVisitsExpandBodiesWithLateSyntaxAndRespectManualRecollapse() async throws {
        let root = URL.temporaryDirectory.appending(path: "radiology-function-visit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = """
        fn outer() {
            fn target() {
                work();
            }
            target();
        }
        fn sibling() {
            other_work();
        }
        """
        try Data(source.utf8).write(to: root.appending(path: "a.rs"))
        try Data("fn other() {\n    next();\n}\n".utf8).write(to: root.appending(path: "b.rs"))
        let domain = "Radiology.FunctionVisit.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let service = SemanticIndexService(indexers: [], cache: IndexCache(root: root.appending(path: "cache")),
                                          tools: ToolDirectory(url: root.appending(path: "tools")))
        let model = AppModel(preferences: preferences, semantics: SemanticModel(service: service))
        await model.openRepository(root, selecting: "a.rs")
        await model.awaitCurrentSourceLoad()
        try model.importCodePath("Visit functions\na.rs:target:Nested function\nb.rs:other:Another file")
        let steps = try #require(model.codePaths.selectedPath).steps
        model.goToCodePathStep(steps[0].id)
        await model.codePathNavigationTask?.value
        await model.awaitCurrentSourceLoad()
        try await waitUntil("initial parse") { model.syntax != nil }
        let buffer = try #require(model.source)
        let syntax = try #require(model.syntax)
        let target = try #require(syntax.enclosingFunctionFold(at: buffer.byteOffset(line: 2, column: 8)))
        let outer = try #require(syntax.enclosingFunctionFold(at: 0))
        let sibling = try #require(syntax.enclosingFunctionFold(at: buffer.byteOffset(line: 7)))

        // Mount the actual reader before syntax, as on a cold file load.
        model.syntax = nil
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: ReaderDetail().environment(model))
        window.contentView = host
        defer { window.contentView = nil }
        try await waitUntil("reader mounted") { host.layoutSubtreeIfNeeded(); return self.reader(in: host) != nil }
        let text = try #require(reader(in: host))
        let coordinator = try #require(text.delegate as? SourceViewerCoordinator)
        #expect(text.selectedRange().location == buffer.utf16Offset(forByte: try #require(model.navigationTarget).byteOffset))
        model.syntax = syntax
        try await waitUntil("late syntax expands target") { coordinator.syntax != nil && !coordinator.isFolded(target.fold) }
        #expect(text.selectedRange().location == buffer.utf16Offset(forByte: try #require(model.navigationTarget).byteOffset))
        #expect(!coordinator.isFolded(outer.fold) && coordinator.isFolded(sibling.fold))
        #expect(text.insertionCaretRect(atCharacter: buffer.utf16Offset(forByte: buffer.byteOffset(line: 3, column: 8))) != nil)

        coordinator.toggleFold(target.fold)
        model.sourceFontSize += 1
        try await waitUntil("font refresh") { text.font?.pointSize == model.sourceFontSize }
        #expect(coordinator.isFolded(target.fold), "font refresh respects manual collapse")
        model.goToCodePathStep(steps[0].id)
        await model.codePathNavigationTask?.value
        try await waitUntil("same-file revisit") { !coordinator.isFolded(target.fold) }
        #expect(coordinator.isFolded(sibling.fold), "revisiting expands only the destination")

        model.goToCodePathStep(steps[1].id)
        await model.codePathNavigationTask?.value
        await model.awaitCurrentSourceLoad()
        try await waitUntil("other file parsed") { model.syntax != nil }
        let otherSyntax = try #require(model.syntax)
        let other = try #require(otherSyntax.enclosingFunctionFold(at: 0))
        try await waitUntil("cross-file visit") {
            guard let current = self.coordinator(in: host) else { return false }
            return current.buffer?.path == "b.rs" && current.syntax != nil && !current.isFolded(other.fold)
        }
        model.goBack()
        await model.awaitCurrentSourceLoad()
        try await waitUntil("Back") {
            guard let current = self.coordinator(in: host) else { return false }
            return current.buffer?.path == "a.rs" && current.syntax != nil && !current.isFolded(target.fold)
        }
        #expect(self.coordinator(in: host)?.isFolded(sibling.fold) == true)
    }
}
