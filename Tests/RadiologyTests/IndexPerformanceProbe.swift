import Foundation
import Testing
@testable import Radiology

/// Opportunistic timing of decoding and normalizing real cached indexes.
/// Runs only when `RADIOLOGY_INDEX_PROBE` names a cache directory.
struct IndexPerformanceProbe {
    @Test func decodeAndNormalizeCachedIndexes() async throws {
        guard let directory = ProcessInfo.processInfo.environment["RADIOLOGY_INDEX_PROBE"] else { return }
        let directoryURL = URL(filePath: directory)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory).filter { $0.hasSuffix(".scip") }
        let metadataURL = directoryURL.appending(path: "index-metadata.json")
        let metadata: IndexMetadata? = try? {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(IndexMetadata.self, from: Data(contentsOf: metadataURL))
        }()
        var inputs: [SemanticIndex.Input] = []
        let clock = ContinuousClock()
        let decodeStart = clock.now
        for file in files {
            let data = try Data(contentsOf: URL(filePath: directory).appending(path: file))
            let project = metadata?.strategies.first(where: { $0.fileName == file })?.strategy.projectDirectory
                ?? file.replacingOccurrences(of: "rust-analyzer_", with: "").replacingOccurrences(of: ".scip", with: "")
            inputs.append(SemanticIndex.Input(index: try SCIPDecoder.decode(data), projectDirectory: project))
        }
        let decoded = clock.now
        let index = SemanticIndex(inputs: inputs)
        let normalized = clock.now
        print("PROBE decode \(decodeStart.duration(to: decoded)) normalize \(decoded.duration(to: normalized)) documents \(index.documentCount) symbols \(index.symbolCount) searchEntries \(index.searchEntries.count)")
        let query = clock.now
        let matches = SymbolSearch.rank("anth", in: index.searchEntries)
        print("PROBE search \(query.duration(to: clock.now)) matches \(matches.count) first \(matches.first?.entry.name ?? "-")")
        #expect(index.documentCount > 0)

        if metadata?.repositoryRoot.hasSuffix("/tkos") == true {
            let relative = "engine/rust/src/app_image.rs"
            let data = try Data(contentsOf: URL(filePath: metadata!.repositoryRoot).appending(path: relative))
            let buffer = try SourceBuffer(path: relative, data: data)
            let document = try #require(await SemanticQueryWorker().documentSemantics(index: index, buffer: buffer))
            let marker = try #require(buffer.text.range(of: "Result<PreparedApp"))
            let utf8 = buffer.text.utf8.distance(from: buffer.text.utf8.startIndex,
                                                 to: marker.lowerBound.samePosition(in: buffer.text.utf8)!) + 7
            let target = try #require(index.target(in: document, at: utf8))
            #expect(target.displayName == "PreparedApp")
            #expect(!target.isOnDefinition)
            let references = try await SemanticQueryWorker().references(of: target.symbol, in: index,
                                                                          root: URL(filePath: metadata!.repositoryRoot))
            print("PROBE tkos app_image PreparedApp definitions \(target.definitions.count) references \(references.total)")
            #expect(!target.definitions.isEmpty)
            #expect(references.total > 0)
        }
    }
}
