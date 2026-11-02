import AppKit
import SwiftUI
import Testing
@testable import Radiology

@MainActor
struct TraitImplementationContextTests {
    private func inputs(root: URL, index: SemanticIndex, path: String, line: Int, column: Int = 0,
                        revision: Int = 1) async throws -> ContextInputs {
        let buffer = try SourceBuffer(path: path, data: Data(contentsOf: root.appending(path: path)))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        return ContextInputs(root: root, buffer: buffer, sourceIdentity: SourceContentIdentity(buffer.data),
            syntax: syntax, caretByte: buffer.byteOffset(line: line, column: column), index: index, indexRevision: revision,
            documentSemantics: index.documents[path].map { DocumentSemantics.make(document: $0, buffer: buffer) }, documentRevision: 1)
    }

    @Test func followsTraitMembersAndImplBodiesWithStableSelection() async throws {
        let f = try TraitImplementationTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let index = try await TraitImplementationTests.enriched(root: f.root, cache: f.cache, index: f.index)
        let context = ContextModel()
        let left = try TraitImplementationTests.id("left/Render#", index: index)
        context.update(try await inputs(root: f.root, index: index, path: "src/lib.rs", line: 5, column: 15))
        #expect(context.implementations.symbol == left && context.implementations.count == 3)
        let row = try #require(context.implementations.groups.first?.items.first)
        context.implementations.selectedID = row.id
        context.update(try await inputs(root: f.root, index: index, path: "src/lib.rs", line: 6, column: 36))
        #expect(context.declaration?.declaration.name == "render")
        #expect(context.implementations.symbol == left && context.implementations.selectedID == row.id)
        // Inside an implementation's method retains trait context.
        context.update(try await inputs(root: f.root, index: index, path: row.path, line: 3, column: 32))
        #expect(context.implementations.symbol == left && context.implementations.count == 3)
        // A reference to the trait in a bound also offers its implementations.
        context.update(try await inputs(root: f.root, index: index, path: "src/lib.rs", line: 20, column: 23))
        #expect(context.implementations.symbol == left)
        context.update(try await inputs(root: f.root, index: index, path: "src/lib.rs", line: 9, column: 15))
        #expect(context.implementations.count == 0 && context.implementations.symbol != nil)
        #expect(context.implementations.selectedID == nil)
        context.update(try await inputs(root: f.root, index: index, path: "src/lib.rs", line: 16, column: 12))
        #expect(context.implementations.symbol == nil)
        context.reset()
        #expect(context.implementations.groups.isEmpty)
    }

    @Test func servicePrecomputesPaneNavigationPreservesCaretAndCacheReloads() async throws {
        let f = try TraitImplementationTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let fake = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(f.root.appending(path: "index.scip").path)' \"$1\"",
            marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: f.cache), tools: ToolDirectory(url: f.cache.appending(path: "tools")))
        let model = AppModel(preferences: try #require(UserDefaults(suiteName: "RadiologyTraits.\(UUID().uuidString)")), semantics: SemanticModel(service: service))
        model.openRepository(f.root)
        try await ContextModelTests.waitUntil { !model.isOpening && model.semantics.status == .current }
        #expect(model.semantics.index.traitImplementations.isPrepared)
        model.openFile("src/lib.rs")
        try await ContextModelTests.waitUntil { model.source?.path == "src/lib.rs" && model.syntax != nil && model.semantics.documentSemantics != nil }
        let buffer = try #require(model.source)
        let departure = buffer.location(atByte: buffer.byteOffset(line: 6, column: 36))
        model.caretMoved(to: departure.byteOffset)
        model.updatePosition(path: buffer.path, byteOffset: 0, line: 1)
        let pane = model.context.implementations
        let row = try #require(pane.groups.first?.items.first)
        let history = model.history.entries
        let navigationRevision = model.navigationRevision
        pane.selectedID = row.id
        #expect(model.navigationRevision == navigationRevision && model.history.entries == history)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 280, height: 180),
            styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: TraitImplementationsPane().environment(model))
        window.contentView = host
        defer { window.contentView = nil }
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
        let table = try #require(implementationTable(in: host))
        #expect(table.numberOfRows == 3, "only impl rows, no file headings or explanatory rows")
        #expect(table.rect(ofRow: 0).height <= 24, "dense native row height")
        // Invoke the same primary action as the row's native Button. Synthetic
        // app mouse events stop the test runner's lifecycle on this host.
        model.openTraitImplementation(id: row.id)
        try await ContextModelTests.waitUntil { model.source?.path == row.path && model.navigationTarget == row.location }
        model.goBack()
        try await ContextModelTests.waitUntil { model.source?.path == departure.path }
        #expect(model.navigationTarget == departure)
        let sink = PublicationSink()
        let snapshot = try #require(model.repository)
        await service.open(snapshot) { await sink.receive($0) }
        try await IndexingTests.waitUntil { sink.latest?.status == .current }
        #expect(sink.latest?.index.traitImplementations.cachedDocumentCount == 2)
        #expect(sink.latest?.index.traitImplementations.parsedDocumentCount == 0)
        model.semantics.repositoryClosed()
        model.context.reset()
    }

    @Test func nativeTraitPaneHasIndependentScrollingAndResizableDivider() async throws {
        let f = try TraitImplementationTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let index = try await TraitImplementationTests.enriched(root: f.root, cache: f.cache, index: f.index)
        let model = AppModel(preferences: try #require(UserDefaults(suiteName: "RadiologyTraitLayout.\(UUID().uuidString)")))
        model.context.update(try await inputs(root: f.root, index: index, path: "src/lib.rs", line: 5, column: 15))
        let pane = model.context.implementations
        let row = try #require(pane.groups.first?.items.first)
        pane.selectedID = row.id
        let host = NSHostingView(rootView: ContextInspectorView().environment(model))
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 820)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        func allSplits(_ view: NSView) -> [NSSplitView] {
            (view as? NSSplitView).map { [$0] } ?? view.subviews.flatMap(allSplits)
        }
        let outer = try #require(allSplits(host).first)
        outer.setPosition(300, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        let lower = try #require(allSplits(outer.arrangedSubviews[1]).first)
        #expect(lower.arrangedSubviews.count == 2)
        let height = lower.arrangedSubviews[0].frame.height
        lower.setPosition(height + 80, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        #expect(lower.arrangedSubviews[0].frame.height > height + 40)
        let expandedHeight = lower.arrangedSubviews[0].frame.height
        lower.setPosition(expandedHeight - 80, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        #expect(lower.arrangedSubviews[0].frame.height < expandedHeight - 40)
        #expect(pane.selectedID == row.id)
        // Optional six-width/appearance component QA, using production rows.
        if let directory = ProcessInfo.processInfo.environment["RADIOLOGY_TRAIT_RENDER_DIR"] {
            try await render(model, to: URL(filePath: directory))
        }
    }

    @Test func beforeAndIndexReplacementClearTraitSelections() async throws {
        let f = try TraitImplementationTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let index = try await TraitImplementationTests.enriched(root: f.root, cache: f.cache, index: f.index)
        let context = ContextModel()
        var request = try await inputs(root: f.root, index: index, path: "src/lib.rs", line: 5, column: 15)
        context.update(request)
        let row = try #require(context.implementations.groups.first?.items.first)
        context.implementations.selectedID = row.id
        request = try await inputs(root: f.root, index: index, path: "src/lib.rs", line: 5, column: 15, revision: 2)
        context.update(request)
        #expect(context.implementations.selectedID == nil)
        var before = try #require(request.buffer)
        before.revision = .before
        request = ContextInputs(root: f.root, buffer: before, sourceIdentity: request.sourceIdentity,
            syntax: request.syntax, caretByte: request.caretByte, index: index, indexRevision: 2,
            documentSemantics: nil, documentRevision: 2)
        context.update(request)
        try await Task.sleep(for: .milliseconds(50))
        #expect(context.implementations.symbol == nil && context.implementations.selectedID == nil)
        context.reset()
    }

    @Test func serviceDoesNotEnrichStaleCachedCoordinatesWhenRegenerationFails() async throws {
        let f = try TraitImplementationTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let fake = FakeIndexer(id: "fake", displayName: "Fake",
            script: "if [ -f STOP ]; then exit 3; fi; cp '\(f.root.appending(path: "index.scip").path)' \"$1\"",
            marker: "Cargo.toml", installable: true)
        let cache = IndexCache(root: f.cache)
        let service = SemanticIndexService(indexers: [fake], cache: cache, tools: ToolDirectory(url: f.cache.appending(path: "tools")))
        let files = ["Cargo.toml", "src/lib.rs", "src/implementations.rs"].map { RepositoryFile(path: $0) }
        let snapshot = RepositorySnapshot(root: f.root, files: files, tree: FileNode.tree(files: files), isGit: false)
        let sink = PublicationSink()
        await service.open(snapshot) { await sink.receive($0) }
        try await IndexingTests.waitUntil { sink.latest?.status == .current }
        #expect(sink.latest?.index.traitImplementations.byTrait.isEmpty == false)
        try Data("changed source\n".utf8).write(to: f.root.appending(path: "src/implementations.rs"))
        try Data().write(to: f.root.appending(path: "STOP"))
        let reload = PublicationSink()
        await service.open(snapshot) { await reload.receive($0) }
        try await IndexingTests.waitUntil { if case .failed = reload.latest?.outcomes.first?.result { true } else { false } }
        #expect(reload.publications.contains { if case .possiblyStale = $0.status { true } else { false } })
        #expect(reload.latest?.index.traitImplementations.byTrait.isEmpty == true)
        #expect(reload.latest?.index.traitImplementations.excludedPaths.count == 2)
        await service.close()
    }

    private func implementationTable(in view: NSView) -> NSTableView? {
        if let table = view as? NSTableView { return table }
        for child in view.subviews {
            if let table = implementationTable(in: child) { return table }
        }
        return nil
    }

    private func render(_ model: AppModel, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for dark in [false, true] {
            for width in [220.0, 280.0, 420.0] {
                let content = TraitImplementationsPane()
                .environment(model)
                .background(Color(nsColor: .textBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 180),
                    styleMask: [.borderless], backing: .buffered, defer: true)
                let host = NSHostingView(rootView: content)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: width, height: 180)
                window.contentView = host
                defer { window.contentView = nil }
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(35))
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appending(path: "\(dark ? "dark" : "light")-\(Int(width)).png"))
            }
        }
    }
}
