import Foundation

/// Finds indexer executables, verifies they actually run, and installs the
/// ones Radiology manages. Every check is a real subprocess with a timeout.
actor ToolProvisioner {
    let tools: ToolDirectory
    private var verified: [String: ToolAvailability] = [:]

    init(tools: ToolDirectory = .default) {
        self.tools = tools
    }

    /// Locates and version-checks an indexer. Results are cached per session
    /// until `forget` or a provisioning run.
    func availability(of indexer: any SemanticIndexer, refresh: Bool = false) async -> ToolAvailability {
        if !refresh, let cached = verified[indexer.id] { return cached }
        let result = await probe(indexer)
        verified[indexer.id] = result
        return result
    }

    func forget(_ indexerID: String) { verified[indexerID] = nil }

    private func probe(_ indexer: any SemanticIndexer) async -> ToolAvailability {
        guard let executable = indexer.locate(in: tools) else {
            return .missing(reason: "\(indexer.displayName) is not installed.")
        }
        let process = IndexerProcess(executable: executable, arguments: indexer.versionArguments,
                                     directory: FileManager.default.temporaryDirectory, environment: ToolDirectory.childEnvironment())
        do {
            let result = try await withTimeout(.seconds(20)) { try await process.run() }
            guard result.succeeded, let version = indexer.parseVersion(stdout: result.stdoutTail, stderr: result.stderrTail) else {
                let detail = [result.stderrTail, result.stdoutTail].first { !$0.isEmpty } ?? "exit status \(result.exitStatus)"
                return .missing(reason: "\(executable.path) did not report a version: \(detail)")
            }
            return .available(executable: executable, version: version)
        } catch {
            process.cancel()
            return .missing(reason: "\(executable.path) could not be checked: \(error.localizedDescription)")
        }
    }

    /// Runs the adapter's installation plan and re-verifies the tool.
    func provision(_ indexer: any SemanticIndexer, progress: @escaping @Sendable (String) -> Void) async throws -> ToolAvailability {
        guard let plan = indexer.provisioning(in: tools) else {
            throw BrowserError.message("Marin Viewer cannot install \(indexer.displayName) automatically. \(indexer.manualInstallation)")
        }
        try FileManager.default.createDirectory(at: tools.url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tools.goBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tools.bin, withIntermediateDirectories: true)
        for step in plan.steps {
            if let prefixIndex = step.arguments.firstIndex(of: "--prefix"), step.arguments.count > prefixIndex + 1 {
                // npm requires its prefix directory to exist before installing into it.
                try FileManager.default.createDirectory(atPath: step.arguments[prefixIndex + 1], withIntermediateDirectories: true)
            }
            progress("Running \(step.commandLine)")
            let process = IndexerProcess(executable: step.executable, arguments: step.arguments, directory: step.directory, environment: step.environment)
            let result = try await process.run { line in progress(line) }
            guard result.succeeded else {
                let detail = [result.stderrTail, result.stdoutTail].first { !$0.isEmpty } ?? ""
                throw BrowserError.message("\(step.executable.lastPathComponent) exited with status \(result.exitStatus) while installing \(indexer.displayName).\n\(detail)")
            }
        }
        verified[indexer.id] = nil
        let availability = await availability(of: indexer, refresh: true)
        guard availability.isAvailable else {
            throw BrowserError.message("Installation finished but \(indexer.displayName) still cannot run. \(availability.reasonText)")
        }
        return availability
    }

    private func withTimeout<T: Sendable>(_ limit: Duration, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: limit)
                throw BrowserError.message("timed out after \(limit)")
            }
            guard let first = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return first
        }
    }
}

extension ToolAvailability {
    var reasonText: String {
        switch self {
        case .available(_, let version): version
        case .missing(let reason): reason
        }
    }
}
