import Foundation

/// A SCIP-producing tool Radiology knows how to find, install, run, and read.
protocol SemanticIndexer: Sendable {
    /// Stable identifier used in cache metadata and diagnostics.
    var id: String { get }
    var displayName: String { get }
    /// `Document.position_encoding` to assume when a document leaves it unspecified.
    var defaultEncoding: ColumnEncoding { get }
    /// The pinned version Radiology installs, when it can install the tool.
    var pinnedVersion: String? { get }
    /// Build-based indexers must run against an isolated copy of the actual
    /// repository inputs rather than writing caches/artifacts to the checkout.
    var requiresIsolatedWorkspace: Bool { get }

    /// Where this indexer applies in the repository; empty means "cannot index".
    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy]
    /// Finds the executable, preferring Radiology's own tools directory.
    func locate(in tools: ToolDirectory) -> URL?
    /// Arguments that print the version, and how to read it from the output.
    var versionArguments: [String] { get }
    func parseVersion(stdout: String, stderr: String) -> String?
    /// The command that writes `index.scip` to `output` for one strategy.
    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand
    /// How to install the tool, or nil when Radiology cannot install it.
    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan?
    /// A hint when the tool cannot be installed automatically.
    var manualInstallation: String { get }
}

extension SemanticIndexer {
    var requiresIsolatedWorkspace: Bool { false }
    var versionArguments: [String] { ["--version"] }
    func parseVersion(stdout: String, stderr: String) -> String? {
        let line = (stdout + "\n" + stderr).split(whereSeparator: \.isNewline).first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return line.map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

enum SemanticIndexerRegistry {
    static let all: [any SemanticIndexer] = [
        RustAnalyzerIndexer(), ScipGoIndexer(), ScipTypeScriptIndexer(), ScipPythonIndexer(), ScipClangIndexer(), ScipKotlinIndexer(),
    ]

    static func indexer(_ id: String) -> (any SemanticIndexer)? { all.first { $0.id == id } }

    /// Every strategy the registry can justify, ordered as registered and capped
    /// so a monorepo with dozens of packages does not launch dozens of tools.
    static func strategies(for inspection: RepositoryInspection, limit: Int = 32) -> (selected: [IndexingStrategy], skipped: [IndexingStrategy]) {
        strategies(for: inspection, indexers: all, limit: limit)
    }
}

/// Radiology's private tools directory under Application Support. Installing
/// here never touches the reader's global toolchains.
struct ToolDirectory: Sendable, Equatable {
    let url: URL

    static var `default`: ToolDirectory {
        ToolDirectory(url: URL.applicationSupportDirectory.appending(path: "Radiology/tools", directoryHint: .isDirectory))
    }

    var goBin: URL { url.appending(path: "go/bin", directoryHint: .isDirectory) }
    func npmPrefix(_ package: String) -> URL { url.appending(path: "npm/\(package)", directoryHint: .isDirectory) }
    func npmBinary(package: String, binary: String) -> URL { npmPrefix(package).appending(path: "node_modules/.bin/\(binary)") }
    var bin: URL { url.appending(path: "bin", directoryHint: .isDirectory) }

    /// First executable among candidates, then the usual PATH-style lookup.
    func locate(_ name: String, candidates: [URL] = []) -> URL? {
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        return ToolLocator.executable(name)
    }

    /// Environment for child tools: PATH with the standard developer locations
    /// so `cargo`, `go`, and `node` resolve even when launched from Finder.
    static func childEnvironment(extra: [String: String] = [:]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let additions = ["\(home)/.cargo/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/local/go/bin", "\(home)/go/bin", "/usr/bin", "/bin"]
        var path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        for addition in additions where !path.contains(addition) { path.append(addition) }
        environment["PATH"] = path.joined(separator: ":")
        environment["HOME"] = environment["HOME"] ?? home
        for (key, value) in extra { environment[key] = value }
        return environment
    }
}
