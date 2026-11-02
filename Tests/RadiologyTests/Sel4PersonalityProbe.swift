import Foundation
import Testing
@testable import Radiology

struct Sel4PersonalityProbe {
    @Test @MainActor func fullPersonalityReindexAndReloadUseTheCompilerUnion() async throws {
        guard let path = ProcessInfo.processInfo.environment["RADIOLOGY_SEL4_PERSONALITY_PROBE_ROOT"] else { return }
        let snapshot = try await RepositoryWorker().open(URL(filePath: path))
        let original = ContentDigest.workingTreeBlobIDs(root: snapshot.root, paths: snapshot.files.map(\.path))
        let service = SemanticIndexService()
        let sink = PublicationSink()
        let started = ContinuousClock.now
        await service.open(snapshot, options: IndexOpenOptions(personality: .sel4)) { await sink.receive($0) }
        try await IndexingTests.waitUntil(.seconds(360)) {
            if case .failed? = sink.latest?.status { return true }
            let result = sink.latest?.outcomes.first?.result
            return sink.latest?.status.isIndexing == false && (result == .generated || result == .cached(stale: false))
                && sink.latest?.index.documents.count ?? 0 > 500
        }
        var publication = try #require(sink.latest)
        if case .failed(let failure) = publication.status { throw BrowserError.message(failure.message + "\n" + failure.stderr) }
        func check(_ publication: SemanticPublication) throws {
            #expect(publication.outcomes.first?.strategy.indexerID == "scip-sel4")
            #expect(publication.outcomes.first?.capability == .partialBuild)
            #expect(publication.outcomes.first?.commandLine?.contains("sel4_pipeline.py") == true)
            #expect(publication.cacheDirectory.lastPathComponent == "sel4")
            for document in publication.index.documents.values {
                let buffer = try SourceBuffer(path: document.path, data: Data(contentsOf: snapshot.root.appending(path: document.path)))
                #expect(DocumentSemantics.make(document: document, buffer: buffer).unmappedCount == 0)
            }
            for name in ["schedule", "doIPCTransfer", "invokeTCB_ThreadControl", "invokeTCB_ThreadControlCaps", "seL4_MappingFailedLookupLevel"] {
                #expect(publication.index.symbols.values.contains {
                    publication.index.displayName($0.id) == name && !publication.index.definitions(of: $0.id).isEmpty
                }, "Missing \(name) in personality output")
            }
            #expect(ContentDigest.workingTreeBlobIDs(root: snapshot.root, paths: snapshot.files.map(\.path)) == original)
        }
        try check(publication)
        let generatedAt = publication.metadata?.generatedAt
        let count = publication.index.documents.count
        if ProcessInfo.processInfo.environment["RADIOLOGY_SEL4_PROBE_REINDEX"] != "0" {
            await service.reindex()
            try await IndexingTests.waitUntil(.seconds(360)) {
                if case .failed? = sink.latest?.status { return true }
                return sink.latest?.outcomes.first?.result == .generated && sink.latest?.status.isIndexing == false
                    && sink.latest?.metadata?.generatedAt != generatedAt
            }
        }
        publication = try #require(sink.latest)
        if case .failed(let failure) = publication.status { throw BrowserError.message(failure.message + "\n" + failure.stderr) }
        try check(publication)
        #expect(publication.index.documents.count == count)
        print("SEL4_PERSONALITY_PROBE pipeline: \(count) documents, \(publication.index.symbolCount) symbols, \(publication.index.documents.values.reduce(0) { $0 + $1.occurrences.count }) occurrences; elapsed=\(started.duration(to: .now)); cache=\(publication.cacheDirectory.path)")
        await service.close()
        let warm = SemanticIndexService()
        let cached = PublicationSink()
        await warm.open(snapshot, options: IndexOpenOptions(personality: .sel4)) { await cached.receive($0) }
        try await IndexingTests.waitUntil { cached.latest?.outcomes.first?.result == .cached(stale: false) && cached.latest?.status.isIndexing == false }
        #expect(cached.latest?.index.documents.count == count)
        await warm.close()
    }
}
