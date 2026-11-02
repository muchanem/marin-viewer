import Foundation
import CryptoKit

/// The reader's own decisions for one repository. Symbol keys are full SCIP
/// symbol strings; package keys are `scheme manager name` (see
/// `SCIPSymbolHeader.packageKey`), without the version. User
/// decisions always beat the built-in policy, and a symbol decision beats a
/// package decision (more specific wins).
///
/// `local N` symbols are never stored: they are numbered per document and
/// renumbered by reindexing after edits, so a saved `local 3` could silently
/// attach to a different binding later. Locals therefore have no persistent
/// marking at all rather than a spelling-based remapping.
struct CriticalityOverrides: Codable, Sendable, Equatable {
    var formatVersion = 1
    var repositoryRoot = ""
    var symbols: [String: Criticality] = [:]
    var packages: [String: Criticality] = [:]

    var isEmpty: Bool { symbols.isEmpty && packages.isEmpty }

    static func isOverridable(symbol: String) -> Bool { !symbol.hasPrefix("local ") && !symbol.isEmpty }

    /// `nil` or `.unknown` removes the decision (back to the built-in policy).
    mutating func setSymbol(_ symbol: String, to value: Criticality?) {
        guard Self.isOverridable(symbol: symbol) else { return }
        if let value, value != .unknown { symbols[symbol] = value } else { symbols[symbol] = nil }
    }

    mutating func setPackage(_ package: String, to value: Criticality?) {
        guard !package.isEmpty else { return }
        if let value, value != .unknown { packages[package] = value } else { packages[package] = nil }
    }

    func symbolDecision(_ symbol: String) -> Criticality? { symbols[symbol] }
    func packageDecision(_ package: String) -> Criticality? { packages[package] }
}

/// Reads and writes one JSON file per repository under Application Support:
/// never inside the viewed repository, and keyed by the same canonical-root
/// hash as the index cache, so reopening restores decisions and a different
/// repository cannot see them.
actor CriticalityOverrideStore {
    let directory: URL
    /// Testing seam: delays `load` so edit-before-load ordering can be exercised.
    private let artificialLoadDelay: Duration
    /// The highest save revision written per file, so an older snapshot that
    /// arrives late can never overwrite a newer one.
    private var writtenRevisions: [URL: Int] = [:]

    init(directory: URL = CriticalityOverrideStore.defaultDirectory, artificialLoadDelay: Duration = .zero) {
        self.directory = directory
        self.artificialLoadDelay = artificialLoadDelay
    }

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Radiology/overrides", directoryHint: .isDirectory)
    }

    nonisolated func fileURL(for root: URL) -> URL {
        directory.appending(path: IndexCache.repositoryID(for: root) + ".json")
    }

    /// A missing or unreadable file is an empty set; a file for a different
    /// root (hash collision or moved cache) is ignored rather than trusted.
    func load(for root: URL) async -> CriticalityOverrides {
        if artificialLoadDelay > .zero { try? await Task.sleep(for: artificialLoadDelay) }
        guard let data = try? Data(contentsOf: fileURL(for: root)),
              let decoded = try? JSONDecoder().decode(CriticalityOverrides.self, from: data),
              decoded.repositoryRoot == Self.canonicalPath(root) else { return CriticalityOverrides() }
        return decoded
    }

    /// Writes a snapshot, or deletes the file when the snapshot is empty.
    /// `revision` orders snapshots: a lower revision than one already written
    /// is skipped; nil writes unconditionally. Deletion failures are real
    /// errors and are reported.
    func save(_ overrides: CriticalityOverrides, for root: URL, revision: Int? = nil) throws {
        let url = fileURL(for: root)
        if let revision {
            if let written = writtenRevisions[url], written > revision { return }
            writtenRevisions[url] = revision
        }
        var stored = overrides
        stored.repositoryRoot = Self.canonicalPath(root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if stored.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(stored).write(to: url, options: .atomic)
    }

    nonisolated static func canonicalPath(_ root: URL) -> String {
        root.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
