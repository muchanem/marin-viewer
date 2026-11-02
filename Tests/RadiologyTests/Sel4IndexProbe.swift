import Foundation
import Testing
@testable import Radiology

/// Opt-in acceptance of prepared seL4 build inputs through the real app service.
struct Sel4IndexProbe {
    @Test @MainActor func preparedIndexPreservesOriginalCoordinatesAndCache() async throws {
        guard let path = ProcessInfo.processInfo.environment["RADIOLOGY_SEL4_PROBE_ROOT"] else { return }
        let snapshot = try await RepositoryWorker().open(URL(filePath: path))
        let root = snapshot.root
        let paths = snapshot.files.map(\.path)
        let original = ContentDigest.workingTreeBlobIDs(root: root, paths: paths)
        let cache = ProcessInfo.processInfo.environment["RADIOLOGY_SEL4_APP_CACHE"] == "1"
            ? IndexCache.default : IndexCache(root: URL(filePath: "/tmp/radiology-sel4-configured-cache"))
        let prebuilt = ProcessInfo.processInfo.environment["RADIOLOGY_SEL4_PREBUILT_INDEX"]
        let adapter: any SemanticIndexer
        if let prebuilt { adapter = PreparedClangIndexer(source: URL(filePath: prebuilt)) }
        else { adapter = ScipClangIndexer() }
        let service = SemanticIndexService(indexers: [adapter], cache: cache)
        let sink = PublicationSink()
        let started = ContinuousClock.now
        await service.open(snapshot) { await sink.receive($0) }
        if prebuilt != nil { await service.reindex() }
        try await IndexingTests.waitUntil(.seconds(180)) {
            guard let latest = sink.latest, !latest.status.isIndexing else { return false }
            return latest.outcomes.first?.result == .generated
                || (prebuilt == nil && latest.outcomes.first?.result == .cached(stale: false))
        }
        let publication = try #require(sink.latest)
        #expect(publication.outcomes.first?.strategy.evidence == ["build/compile_commands.json"])
        #expect(publication.outcomes.first?.capability == .partialBuild)
        let index = publication.index
        #expect(index.documents.count > 300)
        for path in paths where path.hasSuffix(".c") && path != "src/machine/profiler.c" {
            let physical = root.appending(path: path).resolvingSymlinksInPath().path
            let relative = String(physical.dropFirst(root.path.count + 1))
            #expect(index.documents[relative] != nil, "Missing physical C source: \(path)")
        }
        var mapped = 0
        for document in index.documents.values {
            let buffer = try SourceBuffer(path: document.path, data: Data(contentsOf: root.appending(path: document.path)))
            let semantics = DocumentSemantics.make(document: document, buffer: buffer)
            #expect(semantics.unmappedCount == 0, "Invalid coordinates in \(document.path)")
            mapped += semantics.occurrences.count
        }
        for name in ["schedule", "doIPCTransfer", "invokeTCB_ThreadControl", "invokeTCB_ThreadControlCaps", "handleInterrupt"] {
            let symbols = index.symbols.values.filter { index.displayName($0.id) == name }
            #expect(symbols.contains { symbol in
                index.definitions[symbol.id]?.contains { $0.path.hasPrefix("src/") } == true
                    && index.references[symbol.id]?.contains { $0.path.hasPrefix("src/") } == true
            }, "Missing cross-source definition/references for \(name)")
        }
        for name in ["decodeARMSIDControlInvocation", "seL4_MappingFailedLookupLevel", "seL4_Call"] {
            #expect(index.symbols.values.contains { index.displayName($0.id) == name && !index.definitions(of: $0.id).isEmpty },
                    "Missing optional/public API definition for \(name)")
        }
        #expect(ContentDigest.workingTreeBlobIDs(root: root, paths: paths) == original)
        print("SEL4_INDEX_PROBE \(index.documents.count) documents, \(index.symbols.count) symbols, \(mapped) mapped occurrences, \(publication.outcomes.first?.missingFiles.count ?? 0) missing, result=\(String(describing: publication.outcomes.first?.result)), elapsed=\(started.duration(to: .now)), cache=\(cache.directory(for: root).path)")
        await service.close()
        let warm = SemanticIndexService(indexers: [ScipClangIndexer()], cache: cache)
        let reloaded = PublicationSink()
        await warm.open(snapshot) { await reloaded.receive($0) }
        try await IndexingTests.waitUntil(.seconds(60)) { reloaded.latest?.status.isIndexing == false }
        #expect(reloaded.latest?.outcomes.first?.result == .cached(stale: false))
        #expect(reloaded.latest?.index.documents.count == index.documents.count)
        #expect(reloaded.latest?.outcomes.first?.capability == .partialBuild)
        await warm.close()
    }
}
