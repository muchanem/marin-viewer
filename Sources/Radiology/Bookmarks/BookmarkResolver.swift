import Foundation

actor BookmarkResolver {
    private let sources = SourceStore()

    func resolve(_ bookmark: SourceBookmark, root: URL, openBuffer: SourceBuffer?) async throws -> SourceBookmark {
        var buffer: SourceBuffer
        if let openBuffer, openBuffer.path == bookmark.path, openBuffer.revision == bookmark.revision {
            buffer = openBuffer
        } else {
            buffer = try await sources.load(root: root, path: bookmark.path)
            buffer.revision = bookmark.revision
        }
        try Task.checkCancellation()
        let location = try bookmark.resolve(in: buffer)
        return SourceBookmark.make(in: buffer, at: location.byteOffset, label: bookmark.label, id: bookmark.id)
    }
}
