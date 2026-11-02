import Foundation

/// A byte position in one repository document. In a pull request review the
/// same path names two documents, so a location may carry the revision it
/// belongs to; `nil` means "whichever revision the model currently shows for
/// this path" and is resolved to an explicit revision before it is recorded
/// in history or used to read a file.
struct SourceLocation: Hashable, Sendable {
    let path: String
    let byteOffset: Int
    let revision: ReviewRevision?

    init(path: String, byteOffset: Int, revision: ReviewRevision? = nil) {
        self.path = path
        self.byteOffset = byteOffset
        self.revision = revision
    }

    func with(revision: ReviewRevision?) -> SourceLocation {
        SourceLocation(path: path, byteOffset: byteOffset, revision: revision)
    }

    func with(byteOffset: Int) -> SourceLocation {
        SourceLocation(path: path, byteOffset: byteOffset, revision: revision)
    }

    /// Key for per-document restoration points: a Before document and an
    /// After document at one path never share a caret or viewport.
    var positionKey: String { Self.positionKey(path: path, revision: revision) }

    static func positionKey(path: String, revision: ReviewRevision?) -> String {
        revision.map { "\($0.rawValue):\(path)" } ?? path
    }

    /// Same document: same path and same revision.
    func sameDocument(as other: SourceLocation) -> Bool {
        path == other.path && revision == other.revision
    }
}
