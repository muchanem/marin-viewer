import Foundation
import CryptoKit

/// Enriches the batch index before publication. Per-file caches are validated
/// by both exact source bytes and semantic occurrences, never file timestamps.
actor TraitImplementationIndexer {
    private struct FileRecord: Codable {
        let key: String
        let implementations: [TraitImplementation]
        let unresolved: Int
        let hasParseErrors: Bool
    }
    private struct Cache: Codable {
        var version = 1
        var files: [String: FileRecord] = [:]
    }
    private let syntax = SyntaxWorker()
    private let sources = SourceStore()

    func build(index: SemanticIndex, root: URL, cacheDirectory: URL,
               repositoryPaths: [String], excludedPaths: Set<String> = [],
               expectedBlobs: [String: String]? = nil) async throws -> TraitImplementationIndex {
        let cacheURL = cacheDirectory.appending(path: "rust-trait-implementations.json")
        let previous = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        let cached = previous?.version == 1 ? previous?.files ?? [:] : [:]
        var next = Cache()
        var byTrait: [SemanticSymbolID: [TraitImplementation]] = [:]
        var unreadable: [String] = [], errors: [String] = [], excluded: [String] = []
        var unresolved = 0, parsed = 0, hits = 0
        let documents = index.documents.values.filter { $0.path.hasSuffix(".rs") }.sorted { $0.path < $1.path }
        for document in documents {
            try Task.checkCancellation()
            if excludedPaths.contains(document.path) { excluded.append(document.path); continue }
            let buffer: SourceBuffer
            do { buffer = try await sources.load(root: root, path: document.path) }
            catch is CancellationError { throw CancellationError() }
            catch { unreadable.append(document.path); continue }
            let blob = ContentDigest.blobID(of: buffer.data)
            if let expectedBlobs, expectedBlobs[document.path] != blob { excluded.append(document.path); continue }
            let key = Self.key(document: document, blob: blob)
            let record: FileRecord
            if let saved = cached[document.path], saved.key == key {
                record = saved
                hits += 1
            } else {
                let structure = try await syntax.rustTraitImpls(buffer)
                let semantics = DocumentSemantics.make(document: document, buffer: buffer)
                var implementations: [TraitImplementation] = []
                var missing = 0
                for item in structure.impls {
                    let candidates = Set(semantics.occurrences(at: item.traitNameRange.lowerBound).filter {
                        !$0.isDefinition && !$0.symbol.isLocal && $0.byteRange == item.traitNameRange
                    }.map(\.symbol))
                    guard candidates.count == 1, let symbol = candidates.first else { missing += 1; continue }
                    implementations.append(TraitImplementation(traitSymbol: symbol.symbol, path: document.path,
                        byteRange: item.byteRange, traitNameRange: item.traitNameRange,
                        line: buffer.line(atByte: item.byteRange.lowerBound), signature: item.signature,
                        targetType: item.targetType, isNegative: item.isNegative, sourceBlob: blob))
                }
                record = FileRecord(key: key, implementations: implementations, unresolved: missing,
                    hasParseErrors: structure.hasErrors || semantics.unmappedCount > 0)
                parsed += 1
            }
            next.files[document.path] = record
            unresolved += record.unresolved
            if record.hasParseErrors { errors.append(document.path) }
            for item in record.implementations {
                byTrait[SemanticSymbolID(symbol: item.traitSymbol, document: item.path), default: []].append(item)
            }
        }
        try Task.checkCancellation()
        // Cache failure affects speed only. The verified in-memory result is usable.
        if !documents.isEmpty {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(next) { try? data.write(to: cacheURL, options: .atomic) }
        }
        let indexedPaths = Set(documents.map(\.path))
        return TraitImplementationIndex(byTrait: byTrait, unresolvedCount: unresolved, unreadablePaths: unreadable,
            parseErrorPaths: errors, excludedPaths: excluded,
            unindexedFileCount: Set(repositoryPaths.filter { $0.hasSuffix(".rs") }).subtracting(indexedPaths).count,
            isPrepared: true, parsedDocumentCount: parsed, cachedDocumentCount: hits)
    }

    private static func key(document: SemanticDocument, blob: String) -> String {
        var hash = SHA256()
        hash.update(data: Data("trait-impl-v1\u{0}\(blob)\u{0}\(document.encoding)\n".utf8))
        for occurrence in document.occurrences {
            let range = occurrence.range
            hash.update(data: Data("\(occurrence.symbol.symbol)\u{0}\(occurrence.roles):\(range.startLine):\(range.startCharacter):\(range.endLine):\(range.endCharacter)\n".utf8))
        }
        return hash.finalize().map { IndexCache.hexByte($0) }.joined()
    }
}
