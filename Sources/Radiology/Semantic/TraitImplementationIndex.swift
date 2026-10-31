import Foundation

struct TraitImplementationIndex: Sendable {
    let byTrait: [SemanticSymbolID: [TraitImplementation]]
    let unresolvedCount: Int
    let unreadablePaths: [String]
    let parseErrorPaths: [String]
    let excludedPaths: [String]
    let unindexedFileCount: Int
    let isPrepared: Bool
    /// Work counters for cache/performance verification; never UI labels.
    let parsedDocumentCount: Int
    let cachedDocumentCount: Int

    static let unavailable = TraitImplementationIndex(byTrait: [:], unresolvedCount: 0, unreadablePaths: [],
        parseErrorPaths: [], excludedPaths: [], unindexedFileCount: 0, isPrepared: false,
        parsedDocumentCount: 0, cachedDocumentCount: 0)

    var coverageDetail: String {
        var notes = ["Explicit impls in indexed source. Macro-generated impls and inactive configurations may be absent."]
        if unresolvedCount > 0 { notes.append("\(unresolvedCount) impl headers could not be resolved.") }
        if unindexedFileCount > 0 { notes.append("\(unindexedFileCount) Rust files are not indexed.") }
        if !excludedPaths.isEmpty { notes.append("\(excludedPaths.count) files have stale semantic data.") }
        if !unreadablePaths.isEmpty { notes.append("Files could not be read: \(unreadablePaths.joined(separator: ", ")).") }
        if !parseErrorPaths.isEmpty { notes.append("Parse errors: \(parseErrorPaths.joined(separator: ", ")).") }
        return notes.joined(separator: " ")
    }

    var hasGaps: Bool {
        unresolvedCount > 0 || unindexedFileCount > 0 || !unreadablePaths.isEmpty || !parseErrorPaths.isEmpty || !excludedPaths.isEmpty
    }
}
