import Foundation

actor CodePathResolver {
    private let sources = SourceStore()
    private let syntax = SyntaxWorker()

    func resolve(_ step: CodePathStep, root: URL, revision: ReviewRevision?, openBuffer: SourceBuffer? = nil) async throws -> [CodePathDestination] {
        guard step.isValid else { throw BrowserError.message("This code path step is invalid.") }
        var buffer: SourceBuffer
        if let openBuffer, openBuffer.path == step.path, openBuffer.revision == revision { buffer = openBuffer }
        else { buffer = try await sources.load(root: root, path: step.path) }
        try Task.checkCancellation()
        buffer.revision = revision
        let snapshot = try await syntax.parse(buffer)
        try Task.checkCancellation()
        return try CodePathSymbolResolver.destinations(step.function, in: buffer, syntax: snapshot).map {
            CodePathDestination(location: buffer.location(atByte: $0), line: buffer.line(atByte: $0))
        }
    }
}
