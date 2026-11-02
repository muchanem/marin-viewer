import Foundation

/// `scip-clang` for C, C++, and CUDA. It only works from a JSON compilation
/// database. Without one, Radiology supplies explicit best-effort defaults
/// in a temporary database. Emits UTF-8 offsets. The managed binary is pinned
/// to the SHA-256 digest published by the upstream GitHub release API.
struct ScipClangIndexer: SemanticIndexer {
    var jobs = 4
    let id = "scip-clang"
    let displayName = "scip-clang"
    let defaultEncoding = ColumnEncoding.utf8
    let pinnedVersion: String? = "0.4.0"
    static let releaseDigest = "ff042fbc8a029f09f4b69fc7692e290e21c52923593207ee52d4e7439473ec64"
    static let buildRequirement = "C/C++ uses best-effort defaults without compile_commands.json. A real build database improves coverage: for CMake, configure with -DCMAKE_EXPORT_COMPILE_COMMANDS=ON; for Make, capture the build with Bear. Place it at the repository root or in build/."
    let manualInstallation = "Install scip-clang from https://github.com/sourcegraph/scip-clang/releases and place it on PATH or in ~/Library/Application Support/Radiology/tools/bin. The managed 0.4.0 release requires Apple Silicon."

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        if let database = inspection.first(named: "compile_commands.json") {
            return [IndexingStrategy(indexerID: id, projectDirectory: "", evidence: [database], languages: ["C", "C++"])]
        }
        guard !ClangFallbackDatabase.sourcePaths(in: inspection).isEmpty else { return [] }
        return [IndexingStrategy(indexerID: id, projectDirectory: "", evidence: [ClangFallbackDatabase.marker], languages: ["C", "C++"])]
    }

    func locate(in tools: ToolDirectory) -> URL? {
        tools.locate("scip-clang", candidates: [tools.bin.appending(path: "scip-clang")])
    }

    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand {
        IndexCommand(executable: executable,
                     arguments: ["--compdb-path", ClangFallbackDatabase.isFallback(strategy) ? ClangFallbackDatabase.databaseURL(for: output).path : (strategy.evidence.first ?? "compile_commands.json"), "--index-output-path", output.path,
                                 "--supplementary-output-dir", output.path + ".logs", "--show-compiler-diagnostics", "--jobs", String(jobs)]
                                + (ClangFallbackDatabase.isFallback(strategy) ? [] : ["--no-progress-report"]),
                     directory: inspection.root, environment: ToolDirectory.childEnvironment())
    }

    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? {
        #if arch(arm64)
        guard let script = Bundle.module.url(forResource: "install-clang-indexer", withExtension: "sh", subdirectory: "IndexingScripts") else { return nil }
        return ProvisioningPlan(prerequisites: [],
                                summary: "Download scip-clang 0.4.0 for Apple Silicon into Marin Viewer's tools directory and verify its pinned SHA-256 checksum.",
                                steps: [IndexCommand(executable: URL(filePath: "/bin/sh"),
                                                     arguments: [script.path, tools.bin.path, "0.4.0", Self.releaseDigest],
                                                     directory: tools.url, environment: ToolDirectory.childEnvironment())])
        #else
        return nil
        #endif
    }
}
