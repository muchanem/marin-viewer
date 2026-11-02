import Foundation
import Testing
@testable import Radiology

struct CRealDataProbe {
    @Test @MainActor func generatesRealBestEffortIndexWithoutBuildInputs() async throws {
        guard ProcessInfo.processInfo.environment["RADIOLOGY_CPP_FALLBACK_PROBE"] == "1",
              let path = ProcessInfo.processInfo.environment["RADIOLOGY_CPP_PROBE_ROOT"] else { return }
        let root = URL(filePath: path).resolvingSymlinksInPath()
        let snapshot = try await RepositoryWorker().open(root)
        let paths = snapshot.files.map(\.path)
        let original = ContentDigest.workingTreeBlobIDs(root: root, paths: paths)
        let useAppCache = ProcessInfo.processInfo.environment["RADIOLOGY_CPP_FALLBACK_APP_CACHE"] == "1"
        let cache = useAppCache ? IndexCache.default : IndexCache(root: URL(filePath: "/tmp/radiology-real-clang-fallback-cache"))
        let service = SemanticIndexService(indexers: [ScipClangIndexer()], cache: cache)
        let sink = PublicationSink()
        let started = ContinuousClock.now
        print("C_CPP_FALLBACK_PROBE starting \(ClangFallbackDatabase.sourcePaths(in: RepositoryInspection(root: root, paths: paths, isGit: snapshot.isGit)).count) translation units")
        await service.open(snapshot) { await sink.receive($0) }
        try await IndexingTests.waitUntil(.seconds(1800)) { sink.latest?.status.isIndexing == false }
        let publication = try #require(sink.latest)
        #expect(publication.outcomes.first?.capability == .bestEffort)
        if useAppCache { #expect(publication.outcomes.first?.result == .cached(stale: false)) }
        #expect(!publication.index.documents.isEmpty)
        #expect(ContentDigest.workingTreeBlobIDs(root: root, paths: paths) == original)
        let occurrences = publication.index.documents.values.reduce(0) { $0 + $1.occurrences.count }
        print("C_CPP_FALLBACK_PROBE \(publication.index.documents.count) documents, \(publication.index.symbols.count) symbols, \(occurrences) occurrences, \(publication.outcomes.first?.missingFiles.count ?? 0) uncovered source/header files, elapsed=\(started.duration(to: .now)), cache=\(cache.directory(for: root).path)")
        let thread = "l4re-ws/fiasco/src/kern/thread.cpp"
        print("C_CPP_FALLBACK_PROBE thread.cpp occurrences=\(publication.index.documents[thread]?.occurrences.count ?? 0)")
        if let document = publication.index.documents[thread] {
            let buffer = try SourceBuffer(path: thread, data: Data(contentsOf: root.appending(path: thread)))
            #expect(DocumentSemantics.make(document: document, buffer: buffer).unmappedCount == 0)
        }
        await service.close()
    }

    /// Opt-in read-only acceptance against the user's checkout; no compiler
    /// runs, source changes, or writes to the attached repository.
    @Test func parsesRealCAndCppRepositoryInputs() async throws {
        guard let path = ProcessInfo.processInfo.environment["RADIOLOGY_CPP_PROBE_ROOT"] else { return }
        let root = URL(filePath: path)
        let repository = try await RepositoryWorker().open(root)
        let sources = repository.files.filter { ["c", "cpp"].contains(SourceLanguageRegistry.language(for: $0.path)?.id ?? "") }
        var paths: [String] = []
        for ext in ["c", "cc", "cpp", "h"] {
            paths += sources.filter { URL(filePath: $0.path).pathExtension == ext }.prefix(3).map(\.path)
        }
        let thread = "l4re-ws/fiasco/src/kern/thread.cpp"
        if sources.contains(where: { $0.path == thread }) { paths.append(thread) }
        let worker = SyntaxWorker()
        for path in paths {
            let buffer = try SourceBuffer(path: path, data: Data(contentsOf: root.appending(path: path)))
            let syntax = try #require(try await worker.parse(buffer))
            #expect(buffer.data.isEmpty || !syntax.highlights.isEmpty)
            print("C_CPP_PROBE \(path): symbols=\(syntax.symbols.count), folds=\(syntax.folds.count), calls=\(syntax.callSites.count), errors=\(syntax.hasParseErrors)")
            if path == thread {
                #expect(syntax.symbol("type", "Thread"))
                #expect(syntax.folds.contains { $0.kind == "function" })
            }
        }
        print("C_CPP_PROBE \(sources.count) registered source/header files; \(paths.count) parsed samples")
    }
}
