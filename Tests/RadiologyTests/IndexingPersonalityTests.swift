import Foundation
import Testing
@testable import Radiology

@Suite(.serialized)
struct IndexingPersonalityTests {
    @Test func templatesParseAndTOMLRootSettingsAreTyped() throws {
        for personality in IndexingPersonality.allCases {
            let url = try IndexingPersonalityStore.template(personality)
            let settings = try IndexingPersonalitySettings(personality: personality, url: url, data: Data(contentsOf: url))
            #expect(settings.personality == personality)
            #expect(!settings.digest.isEmpty)
        }
        let root = try PersonalityTOML.rootValues("name = 'literal # value' # comment\nindexers = [\n \"a,b\", # comment\n 'c',\n]\n[recipe]\nignored = true")
        #expect(try PersonalityTOML.string(root["name"]) == "literal # value")
        #expect(try PersonalityTOML.strings(root["indexers"]) == ["a,b", "c"])
        #expect(throws: (any Error).self) { try PersonalityTOML.rootValues("id = 'a'\nid = 'b'") }
    }

    @Test func storesInstallWithoutReplacingUserEditsAndRejectBadSettings() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-personalities-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = IndexingPersonalityStore(directory: directory)
        let first = try await store.load(.default)
        var text = String(decoding: first.data, as: UTF8.self)
        text = text.replacing("clang_jobs = 4", with: "clang_jobs = 2")
        try Data(text.utf8).write(to: first.url)
        let edited = try await IndexingPersonalityStore(directory: directory).load(.default)
        #expect(edited.clangJobs == 2)
        #expect(edited.digest != first.digest)
        #expect(ScipClangIndexer(jobs: edited.clangJobs).command(for: IndexingStrategy(indexerID: "scip-clang", projectDirectory: "", evidence: ["compile_commands.json"], languages: ["C"]),
            inspection: RepositoryInspection(root: directory, paths: [], isGit: false), executable: URL(filePath: "/bin/true"),
            output: directory.appending(path: "index.scip"), tools: .default).arguments.suffix(3).contains("2"))
        text = text.replacing("schema_version = 1", with: "schema_version = 9")
        try Data(text.utf8).write(to: first.url)
        await #expect(throws: (any Error).self) { try await store.load(.default) }
        #expect(try String(contentsOf: first.url, encoding: .utf8) == text)
    }

    @Test @MainActor func selectionIsPerRepositoryAndRestoresAcrossPRRoots() throws {
        let preferences = UserDefaults(suiteName: "IndexingPersonalityTests.\(UUID().uuidString)")!
        let root = URL(filePath: "/tmp/personality-repository")
        let other = URL(filePath: "/tmp/personality-other")
        let store = IndexingPersonalityPreferences(preferences: preferences)
        #expect(store.load(for: root) == .default)
        store.save(.sel4, for: root)
        #expect(IndexingPersonalityPreferences(preferences: preferences).load(for: root) == .sel4)
        #expect(store.load(for: other) == .default)
        let model = SemanticModel()
        model.usePersonalityPreferences(preferences)
        let snapshot = RepositorySnapshot(root: URL(filePath: "/tmp/review-snapshot"), files: [], tree: [], isGit: false)
        model.repositoryOpened(snapshot, selectionRoot: root)
        #expect(model.personality == .sel4)
        model.repositoryClosed()
    }

    @Test @MainActor func invalidSettingsFailWithoutFallingBackAndCancellationStopsThePersonality() async throws {
        let root = try IndexingTests.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IndexingPersonalityStore(directory: root.appending(path: "settings"))
        let settings = try await store.load(.sel4)
        let original = settings.data
        try Data("invalid = true\n".utf8).write(to: settings.url)
        let fake = FakeIndexer(id: "scip-sel4", displayName: "seL4", script: "echo preparing; sleep 300", marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: root.appending(path: "cache")), personalityStore: store)
        let sink = PublicationSink()
        await service.open(IndexingTests.snapshot(root), options: IndexOpenOptions(personality: .sel4)) { await sink.receive($0) }
        try await IndexingTests.waitUntil { if case .failed? = sink.latest?.status { true } else { false } }
        #expect(sink.latest?.index.documents.isEmpty == true)
        #expect(sink.latest?.cacheDirectory.lastPathComponent == "sel4")
        try original.write(to: settings.url)
        await service.reindex()
        try await IndexingTests.waitUntil { sink.latest?.outcomes.first?.commandLine?.contains("sleep 300") == true }
        await service.cancel()
        try await IndexingTests.waitUntil { sink.latest?.outcomes.first?.result == .cancelled && sink.latest?.status.isIndexing == false }
        #expect(sink.latest?.index.documents.isEmpty == true)
        await service.close()
    }

    @Test @MainActor func cacheNamespaceSettingsEditsAndReindexKeepTheSelectedPipeline() async throws {
        let root = try IndexingTests.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = IndexingPersonalityStore(directory: root.appending(path: "personalities"))
        let cache = IndexCache(root: root.appending(path: "cache"))
        let script = "cp '\(IndexingTests.fixtureIndex.path)' \"$1\""
        let automatic = FakeIndexer(id: "fake", displayName: "Automatic", script: script, marker: "Cargo.toml", installable: true)
        let sel4 = FakeIndexer(id: "scip-sel4", displayName: "seL4 fixture", script: script, marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [automatic, sel4], cache: cache, personalityStore: store)
        let snapshot = IndexingTests.snapshot(root)
        let sink = PublicationSink()
        await service.open(snapshot, options: IndexOpenOptions(personality: .sel4)) { await sink.receive($0) }
        try await IndexingTests.waitUntil { sink.latest?.outcomes.first?.result == .generated && sink.latest?.status.isIndexing == false }
        #expect(sink.latest?.outcomes.first?.strategy.indexerID == "scip-sel4")
        #expect(sink.latest?.cacheDirectory == cache.selecting(.sel4).directory(for: root))
        let originalDigest = sink.latest?.outcomes.first?.strategy.personalityDigest
        let config = try await store.load(.sel4)
        let edited = String(decoding: config.data, as: UTF8.self).replacing("clang_jobs = 1", with: "clang_jobs = 2")
        try Data(edited.utf8).write(to: config.url)
        await service.reindex()
        try await IndexingTests.waitUntil {
            sink.latest?.outcomes.first?.strategy.personalityDigest != originalDigest
                && sink.latest?.outcomes.first?.result == .generated && sink.latest?.status.isIndexing == false
        }
        let sel4Index = try Data(contentsOf: cache.selecting(.sel4).indexURL(for: root, strategy: sink.latest!.outcomes[0].strategy))
        await service.close()
        let reload = SemanticIndexService(indexers: [automatic, sel4], cache: cache, personalityStore: store)
        let warm = PublicationSink()
        await reload.open(snapshot, options: IndexOpenOptions(personality: .sel4)) { await warm.receive($0) }
        try await IndexingTests.waitUntil { warm.latest?.outcomes.first?.result == .cached(stale: false) && warm.latest?.status.isIndexing == false }
        #expect(warm.latest?.outcomes.first?.strategy.personalityDigest != originalDigest)
        let otherRoot = try IndexingTests.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        await reload.open(IndexingTests.snapshot(otherRoot), options: IndexOpenOptions(personality: .sel4,
            reuseSources: [IndexReuseSource(cache: cache, root: root, label: "working tree")])) { await warm.receive($0) }
        try await IndexingTests.waitUntil {
            warm.latest?.repositoryRoot == otherRoot && warm.latest?.status.isIndexing == false
                && warm.latest?.outcomes.first?.result == .reused(from: "working tree")
        }
        await reload.open(snapshot, options: IndexOpenOptions(personality: .default)) { await warm.receive($0) }
        try await IndexingTests.waitUntil { warm.latest?.personalitySettings?.personality == .default && warm.latest?.status.isIndexing == false }
        #expect(warm.latest?.cacheDirectory == cache.directory(for: root))
        #expect(try Data(contentsOf: cache.selecting(.sel4).indexURL(for: root, strategy: sink.latest!.outcomes[0].strategy)) == sel4Index)
        await reload.close()
    }
}
