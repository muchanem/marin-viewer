import Foundation

/// `rust-analyzer scip <project>` — rust-analyzer's own SCIP emitter. It needs
/// a Cargo project it can load (`cargo metadata` must succeed) and emits UTF-8
/// column offsets. Installed through rustup as a toolchain component.
struct RustAnalyzerIndexer: SemanticIndexer {
    let id = "rust-analyzer"
    let displayName = "rust-analyzer"
    let defaultEncoding = ColumnEncoding.utf8
    let pinnedVersion: String? = nil
    let manualInstallation = "Install rustup from https://rustup.rs, then Marin Viewer can add the rust-analyzer component."

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        inspection.topLevelDirectories(containing: "Cargo.toml").filter { inspection.contains(extension: "rs", under: $0) }.map {
            IndexingStrategy(indexerID: id, projectDirectory: $0, evidence: [$0.isEmpty ? "Cargo.toml" : "\($0)/Cargo.toml"], languages: ["Rust"])
        }
    }

    func locate(in tools: ToolDirectory) -> URL? {
        tools.locate("rust-analyzer", candidates: [URL(filePath: NSHomeDirectory() + "/.cargo/bin/rust-analyzer")])
    }

    func parseVersion(stdout: String, stderr: String) -> String? {
        // rustup's proxy exists even when the component is missing; it then
        // prints "Unknown binary 'rust-analyzer'" on stderr and exits nonzero.
        guard stdout.hasPrefix("rust-analyzer") else { return nil }
        return stdout.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand {
        let project = inspection.root.appending(path: strategy.projectDirectory, directoryHint: .isDirectory)
        var arguments = ["scip", project.path, "--output", output.path, "--exclude-vendored-libraries"]
        if let configuration = Self.writeConfiguration(for: strategy, inspection: inspection, in: tools) {
            arguments += ["--config-path", configuration.path]
        }
        return IndexCommand(executable: executable, arguments: arguments, directory: project, environment: ToolDirectory.childEnvironment())
    }

    static func writeConfiguration(for strategy: IndexingStrategy, inspection: RepositoryInspection, in tools: ToolDirectory) -> URL? {
        let prefix = strategy.projectDirectory.isEmpty ? "" : strategy.projectDirectory + "/"
        let manifestPaths = inspection.paths.filter {
            $0.hasPrefix(prefix) && URL(filePath: $0).lastPathComponent == "Cargo.toml"
        }
        let features = Set(manifestPaths.flatMap { path in
            let text = (try? String(contentsOf: inspection.root.appending(path: path), encoding: .utf8)) ?? ""
            return featureNames(in: text)
        })
        let cfgs = ["debug_assertions", "miri"] + features.sorted().map { "feature=\($0)" }
        let object: [String: Any] = [
            "cargo": ["buildScripts": ["enable": false], "features": "all", "cfgs": cfgs],
            "procMacro": ["enable": false],
        ]
        let safe = strategy.id.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        let url = tools.url.appending(path: "rust-analyzer-scip-\(String(safe)).json")
        do {
            try FileManager.default.createDirectory(at: tools.url, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func featureNames(in manifest: String) -> [String] {
        var inFeatures = false
        var names: [String] = []
        for rawLine in manifest.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "[features]" { inFeatures = true; continue }
            if line.hasPrefix("[") { inFeatures = false }
            guard inFeatures, let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name != "default", name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) {
                names.append(name)
            }
        }
        return names
    }

    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? {
        guard let rustup = ToolLocator.executable("rustup") ?? tools.locate("rustup", candidates: [URL(filePath: NSHomeDirectory() + "/.cargo/bin/rustup")]) else { return nil }
        return ProvisioningPlan(prerequisites: ["rustup"],
                                summary: "Add the rust-analyzer component to the active rustup toolchain.",
                                steps: [IndexCommand(executable: rustup, arguments: ["component", "add", "rust-analyzer"],
                                                     directory: tools.url, environment: ToolDirectory.childEnvironment())])
    }
}
