import SwiftUI
import Testing
@testable import Radiology

@MainActor
struct ContextInspectorLayoutTests {
    private func split(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView { return split }
        for child in view.subviews {
            if let split = split(in: child) { return split }
        }
        return nil
    }

    @Test func nativeDividerResizesBothPanesWithoutChangingContext() async throws {
        let f = try await ContextModelTests.fixture()
        defer { try? FileManager.default.removeItem(at: f.root) }
        let preferences = try #require(UserDefaults(suiteName: "RadiologyLayoutTests.\(UUID().uuidString)"))
        let model = AppModel(preferences: preferences)
        let semantics = DocumentSemantics.make(document: try #require(f.index.documents[f.shapes.path]), buffer: f.shapes)
        model.context.update(ContextInputs(root: f.root, buffer: f.shapes, sourceIdentity: SourceContentIdentity(f.shapes.data), syntax: f.shapesSyntax,
                                           caretByte: f.shapes.byteOffset(line: 8, column: 12), index: f.index, indexRevision: 1,
                                           documentSemantics: semantics, documentRevision: 1))
        try await ContextModelTests.waitUntil { if case .loaded = model.context.references { true } else { false } }
        guard case .loaded(let results) = model.context.references else { return }
        let hit = try #require(results.groups.first?.hits.first)
        model.context.selectedReferenceID = hit.id
        model.context.setReference(hit.id, expanded: true)
        model.context.isDefinitionExpanded = true
        let host = NSHostingView(rootView: ContextInspectorView().environment(model))
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 620)
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        host.layoutSubtreeIfNeeded()
        let split = try #require(self.split(in: host))
        #expect(!split.isVertical)
        #expect(split.arrangedSubviews.count == 2)
        let lower = try #require(self.split(in: split.arrangedSubviews[1]))
        #expect(lower.arrangedSubviews.count == 2)
        split.setPosition(350, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        let topHeight = split.arrangedSubviews[0].frame.height
        let bottomHeight = split.arrangedSubviews[1].frame.height
        split.setPosition(230, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        #expect(split.arrangedSubviews[0].frame.height < topHeight - 80)
        #expect(split.arrangedSubviews[1].frame.height > bottomHeight + 80)
        let middleHeight = lower.arrangedSubviews[0].frame.height
        let bookmarksHeight = lower.arrangedSubviews[1].frame.height
        lower.setPosition(middleHeight + 80, ofDividerAt: 0)
        host.layoutSubtreeIfNeeded()
        #expect(lower.arrangedSubviews[0].frame.height > middleHeight + 40)
        #expect(lower.arrangedSubviews[1].frame.height < bookmarksHeight - 40)
        #expect(model.context.selectedReferenceID == hit.id)
        #expect(model.context.isReferenceExpanded(hit.id) && model.context.isDefinitionExpanded)
        #expect(model.context.declaration?.declaration.name == "area")
        if let output = ProcessInfo.processInfo.environment["RADIOLOGY_CALLER_RENDER_DIR"] {
            try await renderCallers(to: URL(filePath: output))
        }
        if let output = ProcessInfo.processInfo.environment["RADIOLOGY_BOOKMARK_RENDER_DIR"] {
            try renderBookmarks(to: URL(filePath: output))
        }
    }

    private func renderBookmarks(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var buffer = try SourceBuffer(path: "modules/agent/harness/src/session/authentication.rs",
                                      data: Data((0..<12).map { "fn checkpoint\($0)() {}" }.joined(separator: "\n").utf8))
        buffer.revision = .after
        let entries = (0..<12).map { slot -> SourceBookmark in
            var source = buffer
            if slot == 1 { source.revision = .before }
            return SourceBookmark.make(in: source, at: source.byteOffset(line: slot + 1),
                                       label: slot == 0 ? "authenticate_with_session_key" : "checkpoint\(slot)")
        }
        for dark in [false, true] {
            for width in [220.0, 280.0, 420.0] {
                let content = VStack(alignment: .leading, spacing: 0) {
                    ContextRegionHeader(title: "Bookmarks", detail: "PR #758") {
                        Label("Bookmark Location", systemImage: "bookmark").labelStyle(.iconOnly)
                    }
                    VStack(spacing: Theme.spacing) {
                        ForEach(entries) { bookmark in
                            BookmarkRow(bookmark: bookmark, slot: bookmark.line - 1)
                        }
                    }.padding(Theme.inset)
                }
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(InspectorSectionBackground(section: .bookmarks))
                .background(Color(nsColor: .textBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: content)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: width, height: host.fittingSize.height)
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appending(path: "\(dark ? "dark" : "light")-\(Int(width)).png"))
            }
        }
    }

    /// Optional visual QA uses production rows backed by the branching index
    /// fixture; normal tests never write screenshots or present windows.
    private func renderCallers(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let (root, index, hit) = try ReferenceCallTreeTests.fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let buffer = try SourceBuffer(path: hit.location.path, data: Data(contentsOf: root.appending(path: hit.location.path)))
        let syntax = try #require(try await SyntaxWorker().parse(buffer))
        let semantics = DocumentSemantics.make(document: try #require(index.documents[buffer.path]), buffer: buffer)
        let model = AppModel(preferences: try #require(UserDefaults(suiteName: "RadiologyRenderTests.\(UUID().uuidString)")))
        model.context.update(ContextInputs(root: root, buffer: buffer, sourceIdentity: SourceContentIdentity(buffer.data), syntax: syntax,
                                           caretByte: hit.location.byteOffset, index: index, indexRevision: 1,
                                           documentSemantics: semantics, documentRevision: 1))
        model.context.showReferences(of: try #require(index.target(in: semantics, at: hit.location.byteOffset)))
        try await ContextModelTests.waitUntil { if case .loaded = model.context.references { true } else { false } }
        model.context.setReference(hit.id, expanded: true)
        try await ContextModelTests.waitUntil { if case .loaded = model.context.referenceCallTrees[hit.id] { true } else { false } }
        for dark in [false, true] {
            for width in [220.0, 280.0, 420.0] {
                let content = VStack(alignment: .leading, spacing: 0) {
                    DeclarationSummaryView().padding(Theme.inset)
                    ContextRegionHeader(title: "References", detail: "1 reference")
                    ReferenceRow(hit: hit, isExpanded: true, toggle: {}).padding(Theme.inset)
                }
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(nsColor: .textBackgroundColor))
                .environment(model)
                .environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingView(rootView: content)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: width, height: host.fittingSize.height)
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appending(path: "\(dark ? "dark" : "light")-\(Int(width)).png"))
            }
        }
    }
}
