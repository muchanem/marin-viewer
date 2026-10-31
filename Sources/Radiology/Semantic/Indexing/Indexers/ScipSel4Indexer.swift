import Foundation

struct ScipSel4Indexer: SemanticIndexer {
    let settings: IndexingPersonalitySettings
    let id = "scip-sel4"
    let displayName = "seL4 configuration union"
    let defaultEncoding = ColumnEncoding.utf8
    let pinnedVersion: String? = "0.4.0"
    let requiresIsolatedWorkspace = true
    let manualInstallation = ScipClangIndexer().manualInstallation

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        [IndexingStrategy(indexerID: id, projectDirectory: "", evidence: ["CMakeLists.txt"], languages: ["C", "C++"])]
    }
    func locate(in tools: ToolDirectory) -> URL? { ScipClangIndexer().locate(in: tools) }
    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? { ScipClangIndexer().provisioning(in: tools) }
    static func configuration(for output: URL) -> URL { output.appendingPathExtension("personality.toml") }
    static func artifacts(for output: URL) -> URL { output.appendingPathExtension("sel4-build") }

    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand {
        let python = settings.bootstrapPython.lazy.compactMap { name in
            tools.locate(name, candidates: name.contains("/") ? [URL(filePath: (name as NSString).expandingTildeInPath)] : [])
        }.first ?? URL(filePath: "/usr/bin/python3")
        return IndexCommand(executable: python, arguments: ["-u", ScipKotlinIndexer.script("sel4_pipeline.py").path,
            "--repository", inspection.root.path, "--configuration", Self.configuration(for: output).path,
            "--indexer", executable.path, "--output", output.path, "--artifacts", Self.artifacts(for: output).path,
            "--tools-directory", tools.url.path], directory: inspection.root,
            environment: ToolDirectory.childEnvironment(extra: ["PYTHONDONTWRITEBYTECODE": "1", "PYTHONUNBUFFERED": "1"]))
    }
}
