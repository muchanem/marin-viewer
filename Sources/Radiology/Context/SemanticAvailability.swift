import Foundation

/// Why (or whether) the open file has semantic data, kept separate from
/// "nothing semantic is under the caret". A usable repository index (Current,
/// Partial, Possibly Stale, or a prior index while reindexing) is never
/// described as missing just because this particular file is not covered.
enum SemanticAvailability: Equatable, Sendable {
    /// The repository has no usable index yet; the reason comes from status.
    case repositoryNotIndexed(reason: String)
    /// No usable index yet, and indexing is running.
    case indexing(message: String)
    /// The repository index is usable, but has no document for this file.
    case fileNotIndexed
    /// The file is indexed; its occurrence map is still being built.
    case mapping
    case available
    case noFile
    /// A pull request's Before document: only After is indexed, and nothing
    /// is mapped onto Before bytes.
    case revisionNotIndexed

    static func resolve(status: SemanticIndexStatus, index: SemanticIndex, path: String?,
                        mappedPath: String?, revision: ReviewRevision? = nil) -> SemanticAvailability {
        if revision == .before, path != nil { return .revisionNotIndexed }
        if index.documentCount == 0 {
            switch status {
            case .indexing(let progress): return .indexing(message: progress.message)
            case .noIndex(let reason): return .repositoryNotIndexed(reason: reason)
            case .failed(let failure): return .repositoryNotIndexed(reason: failure.message)
            case .partial(let reason), .possiblyStale(let reason): return .repositoryNotIndexed(reason: reason)
            case .current: return .repositoryNotIndexed(reason: "The semantic index has no documents.")
            }
        }
        guard let path else { return .noFile }
        guard index.documents[path] != nil else { return .fileNotIndexed }
        return mappedPath == path ? .available : .mapping
    }

    /// The quiet detail beside the lower region's "Outline" title.
    var headerDetail: String? {
        switch self {
        case .indexing: "Indexing…"
        case .repositoryNotIndexed: "No semantic index"
        case .fileNotIndexed: "File not indexed"
        case .mapping: "Loading semantics…"
        case .revisionNotIndexed: "Before not indexed"
        case .available, .noFile: nil
        }
    }

    /// A sentence for the declaration region when no references can load,
    /// or nil when semantic data is available for the file.
    var explanation: String? {
        switch self {
        case .indexing(let message): "References appear when indexing finishes. \(message)"
        case .repositoryNotIndexed(let reason): reason
        case .fileNotIndexed: "The repository's semantic index does not cover this file, so it has no references. Structure browsing still works."
        case .mapping: "Mapping this file's semantic data…"
        case .revisionNotIndexed: "The Before revision of a pull request is not indexed. Semantic navigation applies to After; structure browsing works in both."
        case .noFile: "Open a source file."
        case .available: nil
        }
    }
}
