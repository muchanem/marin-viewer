import Foundation

/// `scip-python index` — Sourcegraph's Pyright fork. It needs Python 3.10+ on
/// PATH and inspects the active environment with pip. Implemented in
/// TypeScript, so unspecified columns are UTF-16.
struct ScipPythonIndexer: SemanticIndexer {
    static let package = "@sourcegraph/scip-python"
    let id = "scip-python"
    let displayName = "scip-python"
    let defaultEncoding = ColumnEncoding.utf16
    let pinnedVersion: String? = "0.6.6"
    let manualInstallation = "Install Node.js with npm and Python 3.10 or newer, then Marin Viewer can install scip-python."

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        var directories: [String] = []
        for marker in ["pyproject.toml", "setup.py", "setup.cfg", "requirements.txt"] {
            for directory in inspection.topLevelDirectories(containing: marker)
            where !directories.contains(where: { $0 == directory || $0.isEmpty || directory.hasPrefix($0 + "/") })
                && inspection.contains(extension: "py", under: directory) {
                directories.append(directory)
            }
        }
        return directories.map { directory in
            let evidence = ["pyproject.toml", "setup.py", "setup.cfg", "requirements.txt"]
                .map { directory.isEmpty ? $0 : "\(directory)/\($0)" }.filter { inspection.paths.contains($0) }
            return IndexingStrategy(indexerID: id, projectDirectory: directory, evidence: evidence, languages: ["Python"])
        }
    }

    func locate(in tools: ToolDirectory) -> URL? {
        tools.locate("scip-python", candidates: [tools.npmBinary(package: "scip-python", binary: "scip-python")])
    }

    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand {
        let project = inspection.root.appending(path: strategy.projectDirectory, directoryHint: .isDirectory)
        let name = strategy.projectDirectory.isEmpty ? inspection.root.lastPathComponent : URL(filePath: strategy.projectDirectory).lastPathComponent
        return IndexCommand(executable: executable,
                            arguments: ["index", ".", "--project-name", name, "--output", output.path, "--quiet"],
                            directory: project, environment: ToolDirectory.childEnvironment())
    }

    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? {
        guard let npm = ToolLocator.executable("npm"), ToolLocator.executable("node") != nil else { return nil }
        let prefix = tools.npmPrefix("scip-python")
        return ProvisioningPlan(prerequisites: ["node", "npm", "python3"],
                                summary: "Run npm install for \(Self.package)@\(pinnedVersion ?? "latest") into Marin Viewer's tools directory.",
                                steps: [IndexCommand(executable: npm, arguments: ["install", "--no-fund", "--no-audit", "--prefix", prefix.path, "\(Self.package)@\(pinnedVersion ?? "latest")"],
                                                     directory: tools.url, environment: ToolDirectory.childEnvironment())])
    }
}
