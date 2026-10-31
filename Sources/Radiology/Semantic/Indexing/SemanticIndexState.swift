import Foundation

enum SemanticCoverageCapability: String, Sendable, Equatable, Codable {
    case fullWorkspace
    case sourceOnlyNoDeps
    case sysrootOnly
    case partialBuild
    case bestEffort
}

struct MissingSourceFile: Sendable, Equatable, Codable, Identifiable {
    enum Reason: String, Sendable, Equatable, Codable {
        case orphan = "Not declared as a module from a crate root"
        case inactiveConfiguration = "Inactive under the indexed configuration"
        case excludedVendored = "Excluded as vendored source"
        case unknown = "Not emitted by the indexer; reason unknown"
    }
    let path: String
    let reason: Reason
    var id: String { path }
}

/// The reader-facing state of semantic data for the open repository.
enum SemanticIndexStatus: Sendable, Equatable {
    /// Nothing to show: no strategy applies, or generation has not produced anything yet.
    case noIndex(reason: String)
    case indexing(IndexingProgress)
    case current
    case partial(reason: String)
    case possiblyStale(reason: String)
    case failed(IndexingFailure)

    var label: String {
        switch self {
        case .noIndex: "No Index"
        case .indexing: "Indexing"
        case .current: "Current"
        case .partial: "Partial"
        case .possiblyStale: "Possibly Stale"
        case .failed: "Failed"
        }
    }

    var isIndexing: Bool { if case .indexing = self { true } else { false } }
}

struct IndexingProgress: Sendable, Equatable {
    enum Phase: String, Sendable { case inspecting, loadingCache, installing, indexing, loading }
    let phase: Phase
    let strategy: IndexingStrategy?
    let step: Int
    let total: Int
    let message: String
}

/// Everything needed to understand why indexing did not produce a usable
/// result. Output tails are bounded by `IndexerProcess`.
struct IndexingFailure: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case toolMissing(canInstall: Bool)
        case installationFailed
        case processFailed
        case invalidOutput
        case cancelled
    }
    let kind: Kind
    let indexerID: String
    let indexerName: String
    let indexerVersion: String?
    let strategy: IndexingStrategy?
    let commandLine: String?
    let exitStatus: Int32?
    let signal: Int32?
    let stdout: String
    let stderr: String
    let message: String
}

/// The outcome of one strategy in the latest run.
struct StrategyOutcome: Sendable, Equatable, Identifiable {
    enum Result: Sendable, Equatable {
        case pending
        case cached(stale: Bool)
        case generated
        /// Copied from another index whose content digest proved identical
        /// bytes for this strategy's files (`from` is "working tree" or a SHA).
        case reused(from: String)
        case failed(IndexingFailure)
        case cancelled
    }
    let strategy: IndexingStrategy
    var result: Result
    var indexerVersion: String?
    var commandLine: String?
    var documentCount: Int
    var missingFiles: [MissingSourceFile] = []
    var capability: SemanticCoverageCapability = .fullWorkspace
    var cargoError: String?
    /// Bounded output retained for a successful run when it explains partial
    /// coverage or an automatic recovery path.
    var diagnostics: String = ""
    var duration: Duration?
    var id: String { strategy.id }
}

/// A consistent snapshot published atomically to the model.
struct SemanticPublication: Sendable {
    let repositoryRoot: URL
    let index: SemanticIndex
    let status: SemanticIndexStatus
    let outcomes: [StrategyOutcome]
    let skipped: [IndexingStrategy]
    /// Languages present in the repository that no adapter covers.
    let unsupportedLanguages: [String]
    let metadata: IndexMetadata?
    let cacheDirectory: URL
    var personalitySettings: IndexingPersonalitySettings? = nil
}
