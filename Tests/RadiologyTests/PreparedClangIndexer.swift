import Foundation
@testable import Radiology

/// Imports a separately verified compiler union into the normal app cache.
/// The cache record honestly records the copy command; ordinary Reindex still
/// invokes scip-clang. The seL4 recipe documents how to regenerate the union.
struct PreparedClangIndexer: SemanticIndexer {
    let source: URL
    let id = "scip-clang"
    let displayName = "scip-clang (prepared configuration union)"
    let defaultEncoding = ColumnEncoding.utf8
    let pinnedVersion: String? = "0.4.0"
    let manualInstallation = "Prepare and verify the compiler union first."

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        ScipClangIndexer().strategies(for: inspection)
    }

    func locate(in tools: ToolDirectory) -> URL? { ScipClangIndexer().locate(in: tools) }

    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL,
                 output: URL, tools: ToolDirectory) -> IndexCommand {
        IndexCommand(executable: URL(filePath: "/bin/cp"), arguments: [source.path, output.path],
                     directory: inspection.root, environment: ToolDirectory.childEnvironment())
    }

    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? { nil }
}
