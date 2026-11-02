import SwiftUI
import Testing
@testable import Radiology

@MainActor
struct InspectorPaneTests {
    @Test func bookmarksRemainIndependentOfCodePathsSidebar() throws {
        let domain = "RadiologySavedPanes.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let root = URL(filePath: "/tmp/pane-switch")
        // The retired inspector preference must not create a fourth pane.
        preferences.set(true, forKey: "contextPane.codePaths")
        let model = AppModel(preferences: preferences)
        model.bookmarks.activate(BookmarkScope(root: root, pullRequest: nil))
        model.codePaths.activate(root)
        let buffer = try SourceBuffer(path: "boot.c", data: Data("void boot() {}\n".utf8))
        model.source = buffer
        let bookmark = SourceBookmark.make(in: buffer, at: 5, label: "boot")
        model.bookmarks.toggle(bookmark)
        try model.codePaths.importText("Boot\nboot.c:boot:Start")
        let traces = model.codePaths.paths
        let history = model.history.entries
        model.repository = RepositorySnapshot(root: root, files: [], tree: [], isGit: false)
        model.showCodePaths()
        #expect(model.mode == .codePaths && model.inspectorPanes.bookmarks)
        #expect(model.inspectorPanes.visiblePanes(hasTrait: false) == [.references, .definition, .bookmarks])
        #expect(model.sidebarRevealRevision == 1 && model.inspectorRevealRevision == 0)
        model.showCodePaths()
        #expect(model.sidebarRevealRevision == 2, "repeat command can reopen the collapsed left sidebar")
        var restored = InspectorPanes(preferences: preferences)
        #expect(restored.bookmarks)
        model.showBookmarksPane()
        #expect(model.inspectorPanes.bookmarks && model.mode == .codePaths)
        restored = InspectorPanes(preferences: preferences)
        #expect(restored.bookmarks)
        model.inspectorPanes.bookmarks = false
        #expect(!InspectorPanes(preferences: preferences).bookmarks)
        model.showCodePaths()
        #expect(!model.inspectorPanes.bookmarks, "Code Paths respects the independent bookmark preference")
        model.showBookmarksPane()
        #expect(model.bookmarks.entries == [bookmark] && model.codePaths.paths == traces)
        #expect(model.source?.data == buffer.data && model.history.entries == history)
    }

    private func splits(in view: NSView) -> [NSSplitView] {
        (view as? NSSplitView).map { [$0] } ?? view.subviews.flatMap { splits(in: $0) }
    }

    private func tables(in view: NSView) -> [NSTableView] {
        (view as? NSTableView).map { [$0] } ?? view.subviews.flatMap { tables(in: $0) }
    }

    @Test func preferencesPreserveExistingDefaultsAndPersistEveryChoiceIncludingNone() throws {
        let domain = "RadiologyPaneTests.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = AppModel(preferences: preferences)
        #expect(model.inspectorPanes.enabledCount == 4)
        model.inspectorPanes.references = false
        model.inspectorPanes.definition = false
        model.inspectorPanes.implementations = false
        model.inspectorPanes.bookmarks = false
        let restored = AppModel(preferences: preferences)
        #expect(restored.inspectorPanes.enabledCount == 0)
        #expect(restored.inspectorPanes.visiblePanes(hasTrait: true).isEmpty)
        restored.context.reset()
        #expect(restored.inspectorPanes.enabledCount == 0)
        restored.showAllInspectorPanes()
        #expect(AppModel(preferences: preferences).inspectorPanes.areAllEnabled)
    }

    @Test func everyPaneCombinationReflowsNativelyAndPreservesContext() async throws {
        let f = try await ContextModelTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let domain = "RadiologyPaneLayout.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = AppModel(preferences: preferences)
        model.context.update(ContextModelTests.inputs(f, buffer: f.shapes, syntax: f.shapesSyntax,
            caret: f.shapes.byteOffset(line: 8, column: 12)))
        try await ContextModelTests.waitUntil { if case .loaded = model.context.references { true } else { false } }
        guard case .loaded(let results) = model.context.references else { return }
        let hit = try #require(results.groups.first?.hits.first)
        model.context.selectedReferenceID = hit.id
        model.context.setReference(hit.id, expanded: true)
        model.context.isDefinitionExpanded = true
        model.bookmarks.activate(BookmarkScope(root: f.root, pullRequest: nil))
        let bookmark = SourceBookmark.make(in: f.shapes, at: 12, label: "saved reader position")
        model.bookmarks.toggle(bookmark)
        model.bookmarks.selectedID = bookmark.id
        model.source = f.shapes
        model.navigationTarget = f.shapes.location(atByte: 12)
        model.history.visit(f.shapes.location(atByte: 12))
        let history = model.history.entries
        let target = model.navigationTarget
        let revision = model.navigationRevision
        let source = model.source
        let host = NSHostingView(rootView: ContextInspectorView().environment(model))
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 620)
        for mask in 0..<16 {
            var panes = InspectorPanes.all
            panes.references = mask & 1 != 0
            panes.definition = mask & 2 != 0
            panes.implementations = mask & 4 != 0
            panes.bookmarks = mask & 8 != 0
            model.inspectorPanes = panes
            try await Task.sleep(for: .milliseconds(35))
            host.layoutSubtreeIfNeeded()
            let expectedCount = [panes.references, panes.definition, panes.bookmarks].count { $0 }
            let first = splits(in: host).first
            #expect((first == nil) == (expectedCount < 2), "mask \(mask): empty/single-pane layouts have no split")
            if expectedCount >= 2 {
                let split = try #require(first)
                #expect(split.arrangedSubviews.count == 2)
                #expect(split.arrangedSubviews.allSatisfy { $0.frame.height >= 99 })
                let nested = splits(in: split.arrangedSubviews[1]).first
                #expect((nested != nil) == (expectedCount >= 3), "mask \(mask): exactly the active panes participate")
                func allSplits(in view: NSView) -> [NSSplitView] {
                    ((view as? NSSplitView).map { [$0] } ?? []) + view.subviews.flatMap { allSplits(in: $0) }
                }
                #expect(allSplits(in: host).count == expectedCount - 1)
            }
            #expect(model.context.selectedReferenceID == hit.id)
            #expect(model.context.isReferenceExpanded(hit.id) && model.context.isDefinitionExpanded)
            #expect(model.bookmarks.entries == [bookmark] && model.bookmarks.selectedID == bookmark.id)
            #expect(model.navigationTarget == target && model.navigationRevision == revision && model.history.entries == history)
            #expect(model.source?.data == source?.data)
        }
        model.showAllInspectorPanes()
        try await Task.sleep(for: .milliseconds(35))
        host.layoutSubtreeIfNeeded()
        let split = try #require(splits(in: host).first)
        split.setPosition(350, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        let old = split.arrangedSubviews[0].frame.height
        split.setPosition(230, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        #expect(abs(split.arrangedSubviews[0].frame.height - old) > 60)
        if let output = ProcessInfo.processInfo.environment["RADIOLOGY_PANE_RENDER_DIR"] {
            try await render(model: model, to: URL(filePath: output))
        }
    }

    @Test func traitControlsSelectImplementationDefinitionFallbackOrNeither() async throws {
        let f = try TraitImplementationTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let index = try await TraitImplementationTests.enriched(root: f.root, cache: f.cache, index: f.index)
        let domain = "RadiologyTraitPanes.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let model = AppModel(preferences: preferences)
        let buffer = try SourceBuffer(path: "src/lib.rs", data: Data(contentsOf: f.root.appending(path: "src/lib.rs")))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        model.context.update(ContextInputs(root: f.root, buffer: buffer, sourceIdentity: SourceContentIdentity(buffer.data), syntax: syntax,
            caretByte: buffer.byteOffset(line: 5, column: 15), index: index, indexRevision: 1,
            documentSemantics: index.documents[buffer.path].map { DocumentSemantics.make(document: $0, buffer: buffer) }, documentRevision: 1))
        let pane = model.context.implementations
        let row = try #require(pane.groups.first?.items.first)
        pane.selectedID = row.id
        let host = NSHostingView(rootView: ContextInspectorView().environment(model))
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 620)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(35))
        host.layoutSubtreeIfNeeded()
        #expect(tables(in: host).count == 2, "native References and Implementations lists")
        #expect(model.inspectorPanes.visiblePanes(hasTrait: true) == [.references, .implementations, .bookmarks])
        model.inspectorPanes.implementations = false
        try await Task.sleep(for: .milliseconds(35))
        host.layoutSubtreeIfNeeded()
        #expect(tables(in: host).count == 1, "Definition replaces the hidden Implementations list")
        #expect(model.inspectorPanes.visiblePanes(hasTrait: true) == [.references, .definition, .bookmarks])
        model.inspectorPanes.definition = false
        #expect(model.inspectorPanes.visiblePanes(hasTrait: true) == [.references, .bookmarks])
        model.inspectorPanes.references = false
        model.inspectorPanes.bookmarks = false
        model.inspectorPanes.implementations = true
        #expect(model.inspectorPanes.visiblePanes(hasTrait: true) == [.implementations])
        #expect(model.inspectorPanes.visiblePanes(hasTrait: false).isEmpty)
        #expect(pane.selectedID == row.id)
        #expect(pane.count == 3)
        #expect(AppModel(preferences: preferences).inspectorPanes == model.inspectorPanes)
    }

    private func render(model: AppModel, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            for width in [220.0, 280.0, 420.0] {
                for empty in [false, true] {
                    var panes = InspectorPanes.all
                    if empty { panes.references = false; panes.definition = false; panes.implementations = false; panes.bookmarks = false }
                    model.inspectorPanes = panes
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 620),
                        styleMask: [.borderless], backing: .buffered, defer: true)
                    let host = NSHostingView(rootView: ContextInspectorView().environment(model).environment(\.colorScheme, dark ? .dark : .light))
                    host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 620)
                    window.contentView = host
                    defer { window.contentView = nil }
                    host.layoutSubtreeIfNeeded()
                    try await Task.sleep(for: .milliseconds(35))
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try #require(bitmap.representation(using: .png, properties: [:]))
                        .write(to: directory.appending(path: "\(dark ? "dark" : "light")-\(Int(width))-\(empty ? "none" : "all").png"))
                }
            }
        }
    }
}
