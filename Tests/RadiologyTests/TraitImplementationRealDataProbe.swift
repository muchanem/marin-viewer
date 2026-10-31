import Foundation
import Testing
@testable import Radiology

/// Opt-in read-only measurement against an existing app cache. Derived data
/// goes into a disposable /tmp cache, never the repository or original cache.
struct TraitImplementationRealDataProbe {
    @Test func precomputeAndWarmCache() async throws {
        guard let path = ProcessInfo.processInfo.environment["RADIOLOGY_TRAIT_PROBE"] else { return }
        let cache = URL(filePath: path)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(IndexMetadata.self, from: Data(contentsOf: cache.appending(path: "index-metadata.json")))
        let inputs = try metadata.strategies.filter { $0.strategy.indexerID == "rust-analyzer" }.map { record in
            SemanticIndex.Input(index: try SCIPDecoder.decode(Data(contentsOf: cache.appending(path: record.fileName))),
                projectDirectory: record.strategy.projectDirectory, defaultEncoding: .utf8)
        }
        let index = SemanticIndex(inputs: inputs)
        let scratch = FileManager.default.temporaryDirectory.appending(path: "radiology-trait-probe-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: scratch) }
        let root = URL(filePath: metadata.repositoryRoot)
        let start = ContinuousClock.now
        let first = try await TraitImplementationIndexer().build(index: index, root: root, cacheDirectory: scratch,
            repositoryPaths: Array(index.documents.keys))
        let cold = start.duration(to: .now)
        let warmStart = ContinuousClock.now
        let second = try await TraitImplementationIndexer().build(index: index, root: root, cacheDirectory: scratch,
            repositoryPaths: Array(index.documents.keys))
        print("TRAIT_PROBE documents=\(index.documentCount) traits=\(first.byTrait.count) impls=\(first.byTrait.values.reduce(0) { $0 + $1.count }) unresolved=\(first.unresolvedCount) unreadable=\(first.unreadablePaths.count) parseErrors=\(first.parseErrorPaths.count) cold=\(cold) warm=\(warmStart.duration(to: .now)) cacheHits=\(second.cachedDocumentCount) reparsed=\(second.parsedDocumentCount)")
        #expect(second.parsedDocumentCount == 0)
        #expect(first.byTrait == second.byTrait)
    }
}
