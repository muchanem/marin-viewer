import Foundation

/// What the repository looks like to the indexer adapters: the file list plus
/// the build and project files that pick a strategy.
struct RepositoryInspection: Sendable {
    let root: URL
    let paths: [String]
    let isGit: Bool
    /// Git blob ids per path when the root is an exact snapshot of a commit
    /// (from `git ls-tree`). Nil for a working tree, whose ids are hashed
    /// only when an index is generated.
    var blobIDs: [String: String]? = nil

    /// Directories (relative, "" for the root) containing a file with this
    /// exact name, shallowest first, excluding any nested under another match.
    func topLevelDirectories(containing fileName: String) -> [String] {
        let directories = paths.filter { URL(filePath: $0).lastPathComponent == fileName }
            .map { path -> String in
                let components = path.split(separator: "/").dropLast()
                return components.joined(separator: "/")
            }
            .sorted { ($0.count, $0) < ($1.count, $1) }
        var result: [String] = []
        for directory in directories where !result.contains(where: { $0.isEmpty || directory.hasPrefix($0 + "/") }) {
            result.append(directory)
        }
        return result
    }

    func count(extensions: Set<String>, under directory: String) -> Int {
        paths.count { path in
            (directory.isEmpty || path.hasPrefix(directory + "/")) && extensions.contains(URL(filePath: path).pathExtension.lowercased())
        }
    }

    func contains(extension ext: String, under directory: String) -> Bool {
        paths.contains { path in
            (directory.isEmpty || path.hasPrefix(directory + "/")) && URL(filePath: path).pathExtension.lowercased() == ext
        }
    }

    func first(named fileName: String) -> String? {
        paths.filter { URL(filePath: $0).lastPathComponent == fileName }
            .min { ($0.split(separator: "/").count, $0) < ($1.split(separator: "/").count, $1) }
    }
}

/// One concrete indexing run: an adapter applied to one project directory.
struct IndexingStrategy: Sendable, Hashable, Identifiable, Codable {
    let indexerID: String
    /// Repository-relative project directory; "" is the root.
    let projectDirectory: String
    /// The build or project files that justified this strategy.
    let evidence: [String]
    /// Languages this run should cover, for the status display.
    let languages: [String]
    /// Source files of those languages under the project directory, so the
    /// status can say how many of them the indexer actually covered.
    var sourceFileCount = 0
    /// Settings and bundled pipeline bytes are part of cache/reuse identity.
    var personalityDigest: String? = nil

    var id: String { projectDirectory.isEmpty ? indexerID : "\(indexerID)@\(projectDirectory)" }
    /// Safe for use as a cache file name.
    var cacheFileName: String {
        let safe = id.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return String(safe) + ".scip"
    }
}

struct IndexCommand: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
    let directory: URL
    var environment: [String: String]

    var commandLine: String {
        ([executable.path] + arguments).map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
    }
}

/// Whether an indexer executable is usable right now.
enum ToolAvailability: Sendable, Equatable {
    case available(executable: URL, version: String)
    case missing(reason: String)

    var executable: URL? { if case .available(let executable, _) = self { executable } else { nil } }
    var version: String? { if case .available(_, let version) = self { version } else { nil } }
    var isAvailable: Bool { executable != nil }
}

/// How Radiology installs a tool into its own tools directory, and what the
/// machine must already have for that to work.
struct ProvisioningPlan: Sendable, Equatable {
    /// Executable names that must exist on the machine first (`rustup`, `go`, `npm`).
    let prerequisites: [String]
    /// Shown before installing, so the reader knows what will run.
    let summary: String
    /// Commands run in order from the tools directory.
    let steps: [IndexCommand]
}
