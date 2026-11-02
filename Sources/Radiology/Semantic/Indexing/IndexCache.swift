import Foundation
import CryptoKit

/// Where generated indexes live: never inside the viewed repository.
struct IndexCache: Sendable, Equatable {
    let root: URL
    /// A flat cache is one directory for exactly one revision of one
    /// repository (`…/revisions/<sha>/index`); the root argument of its
    /// methods is ignored. The default cache keys directories by root hash.
    let flat: Bool
    var personality: IndexingPersonality? = nil

    init(root: URL, flat: Bool = false) {
        self.root = root
        self.flat = flat
    }

    static var `default`: IndexCache {
        IndexCache(root: URL.cachesDirectory.appending(path: "Radiology/repositories", directoryHint: .isDirectory))
    }

    /// A stable identifier for one repository root path.
    static func repositoryID(for root: URL) -> String {
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.resolvingSymlinksInPath().path.utf8))
        return digest.prefix(8).map { Self.hexByte($0) }.joined()
    }

    static func hexByte(_ byte: UInt8) -> String {
        let text = String(byte, radix: 16)
        return byte < 16 ? "0" + text : text
    }

    func directory(for root: URL) -> URL {
        let base = flat ? self.root : self.root.appending(path: Self.repositoryID(for: root), directoryHint: .isDirectory)
        return personality == .sel4 ? base.appending(path: "personalities/sel4", directoryHint: .isDirectory) : base
    }

    func selecting(_ personality: IndexingPersonality?) -> IndexCache {
        var result = self; result.personality = personality; return result
    }

    func metadataURL(for root: URL) -> URL { directory(for: root).appending(path: "index-metadata.json") }
    func indexURL(for root: URL, strategy: IndexingStrategy) -> URL { directory(for: root).appending(path: strategy.cacheFileName) }

    func loadMetadata(for root: URL) -> IndexMetadata? {
        guard let data = try? Data(contentsOf: metadataURL(for: root)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(IndexMetadata.self, from: data)
    }

    func save(_ metadata: IndexMetadata, for root: URL) throws {
        try FileManager.default.createDirectory(at: directory(for: root), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = metadataURL(for: root)
        let temporary = url.appendingPathExtension("tmp")
        try encoder.encode(metadata).write(to: temporary, options: .atomic)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }

    func remove(for root: URL) {
        try? FileManager.default.removeItem(at: directory(for: root))
    }
}

/// What the cached index was built from. Comparing it with a fresh
/// `RepositoryFingerprint` decides Current versus Possibly Stale.
struct IndexMetadata: Codable, Sendable, Equatable {
    struct StrategyRecord: Codable, Sendable, Equatable {
        let strategy: IndexingStrategy
        let indexerVersion: String
        let commandLine: String
        let fileName: String
        let documentCount: Int
        let duration: Double
        let missingFiles: [MissingSourceFile]
        let capability: SemanticCoverageCapability
        let cargoError: String?
        let diagnostics: String
        /// Exact-bytes provenance (format 3): `ContentDigest.digest` of the
        /// files this strategy's output depends on. Absent in format-2
        /// records, which therefore never qualify for reuse.
        var contentDigest: String? = nil
        /// The revision (or "working tree") whose identical-bytes index this
        /// record's file was copied from, when it was not generated here.
        var reusedFrom: String? = nil
    }

    var repositoryRoot: String
    var headCommit: String?
    var workingTreeFingerprint: String
    var buildFingerprint: String
    var generatedAt: Date
    var strategies: [StrategyRecord]
    var skippedStrategies: [IndexingStrategy]
    var formatVersion = 3
    /// The exact commit a snapshot index describes; nil for a working tree.
    var revision: String? = nil
}

/// Another cache whose format-3 strategy records may be reused when their
/// content digest equals the one about to be generated.
struct IndexReuseSource: Sendable, Equatable {
    let cache: IndexCache
    /// The root the source cache is keyed by (ignored by flat caches).
    let root: URL
    /// Shown as the provenance of reused data ("working tree", a short SHA).
    let label: String
}

/// How an index run should treat its cache and provenance.
struct IndexOpenOptions: Sendable, Equatable {
    /// Nil preserves direct service callers' original adapter configuration.
    /// The app always supplies its remembered Default or seL4 personality.
    var personality: IndexingPersonality? = nil
    /// Replaces the service's default cache (a revision's flat cache).
    var cache: IndexCache? = nil
    var reuseSources: [IndexReuseSource] = []
    /// The exact commit being indexed, recorded in metadata; nil for a working tree.
    var revision: String? = nil
    /// Blob ids of the snapshot's files (from `git ls-tree`), the exact-bytes
    /// provenance for freshness and reuse. Nil for a working tree.
    var blobIDs: [String: String]? = nil
}

/// Fingerprints of the working tree and of the build files that steer
/// indexers. Both hash paths with sizes and modification times; the build
/// fingerprint also hashes the files' contents because they are small.
struct RepositoryFingerprint: Sendable, Equatable {
    let headCommit: String?
    let workingTree: String
    let build: String

    static let buildFileNames: Set<String> = [
        "Cargo.toml", "Cargo.lock", "go.mod", "go.sum", "go.work", "package.json", "package-lock.json", "yarn.lock",
        "pnpm-lock.yaml", "tsconfig.json", "jsconfig.json", "pyproject.toml", "setup.py", "setup.cfg", "requirements.txt",
        "compile_commands.json", "CMakeLists.txt", "build.gradle", "build.gradle.kts", "pom.xml", "rust-toolchain.toml",
    ]

    static func compute(root: URL, paths: [String], headCommit: String?) -> RepositoryFingerprint {
        var tree = SHA256()
        var build = SHA256()
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        for path in paths.sorted() {
            let url = root.appending(path: path)
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            let stamp = "\(path)\u{0}\(values.fileSize ?? 0)\u{0}\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)\n"
            tree.update(data: Data(stamp.utf8))
            if buildFileNames.contains(url.lastPathComponent) {
                build.update(data: Data(path.utf8))
                if let contents = try? Data(contentsOf: url), contents.count < 4 * 1024 * 1024 { build.update(data: contents) }
            }
        }
        return RepositoryFingerprint(headCommit: headCommit, workingTree: hex(tree.finalize()), build: hex(build.finalize()))
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { IndexCache.hexByte($0) }.joined() }

    /// Why a cached index no longer matches, or nil when it is current.
    func stalenessReason(comparedTo metadata: IndexMetadata) -> String? {
        if metadata.headCommit != headCommit, headCommit != nil || metadata.headCommit != nil {
            return "The checked-out commit changed since the index was generated."
        }
        if metadata.buildFingerprint != build { return "Build or project files changed since the index was generated." }
        if metadata.workingTreeFingerprint != workingTree { return "Files changed since the index was generated." }
        return nil
    }
}
