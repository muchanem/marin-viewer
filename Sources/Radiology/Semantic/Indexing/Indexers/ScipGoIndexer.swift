import Foundation

/// `scip-go` from the scip-code organization. Runs from a module root and
/// emits UTF-8 offsets. Installed with `go install` into Radiology's GOBIN.
struct ScipGoIndexer: SemanticIndexer {
    static let module = "github.com/scip-code/scip-go/cmd/scip-go"
    let id = "scip-go"
    let displayName = "scip-go"
    let defaultEncoding = ColumnEncoding.utf8
    let pinnedVersion: String? = "v0.2.7"
    let manualInstallation = "Install Go from https://go.dev/dl, then Marin Viewer can run go install for scip-go."

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        inspection.topLevelDirectories(containing: "go.mod").filter { inspection.contains(extension: "go", under: $0) }.map {
            IndexingStrategy(indexerID: id, projectDirectory: $0, evidence: [$0.isEmpty ? "go.mod" : "\($0)/go.mod"], languages: ["Go"])
        }
    }

    func locate(in tools: ToolDirectory) -> URL? {
        tools.locate("scip-go", candidates: [tools.goBin.appending(path: "scip-go"), URL(filePath: NSHomeDirectory() + "/go/bin/scip-go")])
    }

    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand {
        let project = inspection.root.appending(path: strategy.projectDirectory, directoryHint: .isDirectory)
        return IndexCommand(executable: executable, arguments: ["--output", output.path], directory: project,
                            environment: ToolDirectory.childEnvironment())
    }

    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? {
        guard let go = ToolLocator.executable("go") ?? tools.locate("go", candidates: [URL(filePath: "/usr/local/go/bin/go")]) else { return nil }
        return ProvisioningPlan(prerequisites: ["go"],
                                summary: "Run go install for scip-go \(pinnedVersion ?? "") into Marin Viewer's tools directory.",
                                steps: [IndexCommand(executable: go, arguments: ["install", "\(Self.module)@\(pinnedVersion ?? "latest")"],
                                                     directory: tools.url,
                                                     environment: ToolDirectory.childEnvironment(extra: ["GOBIN": tools.goBin.path, "GOFLAGS": "-mod=mod"]))])
    }
}
