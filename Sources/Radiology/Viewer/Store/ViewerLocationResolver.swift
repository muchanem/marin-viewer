import Foundation

/// Finds the line of a function named by a diagram box or a session's `open_location`, with the
/// same tree-sitter symbol matching Radiology's code paths use (`CodePathSymbolResolver`).
actor ViewerLocationResolver {
    private let sources = SourceStore()
    private let syntax = SyntaxWorker()

    /// The 1-based line of the first declaration of `function` (`Class.method` or a bare name) in
    /// `path` under `root`, or nil when the file or the symbol is missing.
    func line(of function: String, path: String, root: URL) async -> Int? {
        do {
            let buffer = try await sources.load(root: root, path: path)
            let snapshot = try await syntax.parse(buffer)
            guard let offset = try CodePathSymbolResolver.destinations(function, in: buffer, syntax: snapshot).first else { return nil }
            return buffer.line(atByte: offset)
        } catch {
            return nil
        }
    }
}
