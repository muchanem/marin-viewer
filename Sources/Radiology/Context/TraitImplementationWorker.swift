import Foundation

actor TraitImplementationWorker {
    private let sources = SourceStore()

    private func verifiedBuffer(for item: TraitImplementation, root: URL) async throws -> SourceBuffer {
        let buffer = try await sources.load(root: root, path: item.path)
        guard ContentDigest.blobID(of: buffer.data) == item.sourceBlob,
              item.byteRange.lowerBound >= 0, item.byteRange.upperBound <= buffer.data.count else {
            throw BrowserError.message("\(item.path) changed since implementations were indexed. Reload or reindex to refresh them.")
        }
        return buffer
    }

    func resolve(_ item: TraitImplementation, root: URL) async throws -> SourceLocation {
        _ = try await verifiedBuffer(for: item, root: root)
        try Task.checkCancellation()
        return item.location
    }
}
