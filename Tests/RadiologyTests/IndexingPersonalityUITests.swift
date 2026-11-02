import SwiftUI
import Testing
@testable import Radiology

@MainActor
struct IndexingPersonalityUITests {
    @Test func switchingPersonalityPreservesReaderAndNativePopoverLayout() async throws {
        let root = try IndexingTests.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let domain = "PersonalityUI.\(UUID().uuidString)"
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let script = "cp '\(IndexingTests.fixtureIndex.path)' \"$1\""
        let indexers = [
            FakeIndexer(id: "fake", displayName: "Automatic", script: script, marker: "Cargo.toml", installable: true),
            FakeIndexer(id: "scip-sel4", displayName: "seL4", script: script, marker: "Cargo.toml", installable: true)]
        let service = SemanticIndexService(indexers: indexers, cache: IndexCache(root: root.appending(path: "cache")),
            personalityStore: IndexingPersonalityStore(directory: root.appending(path: "settings")))
        let model = AppModel(preferences: preferences, semantics: SemanticModel(service: service))
        model.openRepository(root)
        try await IndexingTests.waitUntil { model.repository != nil && model.semantics.hasIndex && !model.semantics.status.isIndexing }
        model.openFile("src/lib.rs")
        try await IndexingTests.waitUntil { model.source != nil && !model.isLoadingSource }
        let source = model.source?.data, history = model.history.entries, target = model.navigationTarget
        model.semantics.personality = .sel4
        try await IndexingTests.waitUntil { model.semantics.personalitySettings?.personality == .sel4 && !model.semantics.status.isIndexing }
        #expect(model.source?.data == source && model.history.entries == history && model.navigationTarget == target)
        #expect(IndexingPersonalityPreferences(preferences: preferences).load(for: root) == .sel4)
        model.semantics.personality = .default
        model.semantics.personality = .sel4
        try await IndexingTests.waitUntil { model.semantics.personalitySettings?.personality == .sel4 && !model.semantics.status.isIndexing }
        #expect(model.source?.data == source && model.history.entries == history)
        let generatedAt = model.semantics.metadata?.generatedAt
        model.reindexRepository()
        try await IndexingTests.waitUntil { model.semantics.metadata?.generatedAt != generatedAt && !model.semantics.status.isIndexing }
        #expect(model.semantics.outcomes.first?.strategy.indexerID == "scip-sel4")
        if let path = ProcessInfo.processInfo.environment["RADIOLOGY_PERSONALITY_RENDER_DIR"] {
            let output = URL(filePath: path)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for dark in [false, true] {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 500), styleMask: [.borderless], backing: .buffered, defer: true)
                let host = NSHostingView(rootView: SemanticStatusPopover().environment(model)
                    .background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, dark ? .dark : .light))
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                host.frame = NSRect(x: 0, y: 0, width: 440, height: 500)
                window.contentView = host
                defer { window.contentView = nil }
                try await Task.sleep(for: .milliseconds(50))
                host.setFrameSize(host.fittingSize)
                host.layoutSubtreeIfNeeded()
                #expect(host.frame.width == 440 && host.frame.height < 750)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: output.appending(path: dark ? "dark.png" : "light.png"))
            }
        }
        model.semantics.repositoryClosed()
    }
}
