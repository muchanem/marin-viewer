import Foundation

/// `scip-typescript index` for TypeScript and JavaScript. Implemented in
/// TypeScript, so unspecified columns are UTF-16. Installed with npm into a
/// private prefix; projects still need their own `node_modules` for full
/// cross-package resolution.
struct ScipTypeScriptIndexer: SemanticIndexer {
    static let package = "@sourcegraph/scip-typescript"
    let id = "scip-typescript"
    let displayName = "scip-typescript"
    let defaultEncoding = ColumnEncoding.utf16
    let pinnedVersion: String? = "0.4.0"
    let manualInstallation = "Install Node.js 22 or newer with npm, then Marin Viewer can install scip-typescript."

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        var strategies: [IndexingStrategy] = []
        var covered: [String] = []
        for directory in inspection.topLevelDirectories(containing: "tsconfig.json") {
            strategies.append(IndexingStrategy(indexerID: id, projectDirectory: directory,
                                               evidence: [directory.isEmpty ? "tsconfig.json" : "\(directory)/tsconfig.json"],
                                               languages: ["TypeScript", "JavaScript"]))
            covered.append(directory)
        }
        for directory in inspection.topLevelDirectories(containing: "package.json")
        where !covered.contains(where: { $0.isEmpty || directory == $0 || directory.hasPrefix($0 + "/") }) {
            let hasScripts = ["js", "jsx", "mjs", "cjs", "ts", "tsx"].contains { inspection.contains(extension: $0, under: directory) }
            guard hasScripts else { continue }
            strategies.append(IndexingStrategy(indexerID: id, projectDirectory: directory,
                                               evidence: [directory.isEmpty ? "package.json" : "\(directory)/package.json"],
                                               languages: ["JavaScript", "TypeScript"]))
        }
        return strategies
    }

    func locate(in tools: ToolDirectory) -> URL? {
        tools.locate("scip-typescript", candidates: [tools.npmBinary(package: "scip-typescript", binary: "scip-typescript")])
    }

    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand {
        let project = inspection.root.appending(path: strategy.projectDirectory, directoryHint: .isDirectory)
        var arguments = ["index", "--output", output.path, "--no-progress-bar"]
        if strategy.evidence.contains(where: { $0.hasSuffix("package.json") }) { arguments.append("--infer-tsconfig") }
        return IndexCommand(executable: executable, arguments: arguments, directory: project, environment: ToolDirectory.childEnvironment())
    }

    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? {
        guard let npm = ToolLocator.executable("npm"), ToolLocator.executable("node") != nil else { return nil }
        let prefix = tools.npmPrefix("scip-typescript")
        return ProvisioningPlan(prerequisites: ["node", "npm"],
                                summary: "Run npm install for \(Self.package)@\(pinnedVersion ?? "latest") into Marin Viewer's tools directory.",
                                steps: [IndexCommand(executable: npm, arguments: ["install", "--no-fund", "--no-audit", "--prefix", prefix.path, "\(Self.package)@\(pinnedVersion ?? "latest")"],
                                                     directory: tools.url, environment: ToolDirectory.childEnvironment())])
    }
}
