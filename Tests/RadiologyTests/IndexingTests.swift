import Foundation
import Testing
@testable import Radiology

/// A fake SCIP tool: `/bin/sh` scripts stand in for an indexer so the service
/// can be exercised without any language toolchain.
struct FakeIndexer: SemanticIndexer {
    let id: String
    let displayName: String
    var defaultEncoding = ColumnEncoding.utf8
    let pinnedVersion: String? = "1.0"
    let manualInstallation = "Install the fake tool."
    /// Shell script given the output path as `$1`.
    let script: String
    let marker: String
    let installable: Bool
    let versionArguments = ["-c", "echo fake 1.0"]
    var languages: [String] = ["Rust"]
    var requiresIsolatedWorkspace = false

    func strategies(for inspection: RepositoryInspection) -> [IndexingStrategy] {
        inspection.topLevelDirectories(containing: marker).map {
            IndexingStrategy(indexerID: id, projectDirectory: $0, evidence: [marker], languages: languages)
        }
    }
    func locate(in tools: ToolDirectory) -> URL? { installable ? URL(filePath: "/bin/sh") : nil }
    func command(for strategy: IndexingStrategy, inspection: RepositoryInspection, executable: URL, output: URL, tools: ToolDirectory) -> IndexCommand {
        IndexCommand(executable: executable, arguments: ["-c", script, "fake", output.path], directory: inspection.root, environment: ["PATH": "/bin:/usr/bin"])
    }
    func provisioning(in tools: ToolDirectory) -> ProvisioningPlan? { nil }
}

@MainActor
final class PublicationSink {
    var publications: [SemanticPublication] = []
    var latest: SemanticPublication? { publications.last }
    func receive(_ publication: SemanticPublication) { publications.append(publication) }
}

@Suite(.serialized)
struct IndexingTests {
    static let fixtureIndex = SemanticIndexTests.fixtureRoot.appending(path: "index.scip")

    static func temporaryRepository() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-idx-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
        for name in ["Cargo.toml", "src/lib.rs", "src/shapes.rs"] {
            try FileManager.default.copyItem(at: SemanticIndexTests.fixtureRoot.appending(path: name), to: root.appending(path: name))
        }
        return root.resolvingSymlinksInPath()
    }

    static func snapshot(_ root: URL) -> RepositorySnapshot {
        let files = ["Cargo.toml", "src/lib.rs", "src/shapes.rs"].map { RepositoryFile(path: $0) }
        return RepositorySnapshot(root: root, files: files, tree: FileNode.tree(files: files), isGit: false)
    }

    static func waitUntil(_ timeout: Duration = .seconds(60), _ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while await !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await condition(), "timed out")
    }

    @Test func processCapturesStatusAndBoundedOutput() async throws {
        let ok = IndexerProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "echo out; echo err 1>&2; exit 0"], directory: URL(filePath: "/tmp"), environment: [:])
        let result = try await ok.run()
        #expect(result.succeeded)
        #expect(result.stdoutTail == "out")
        #expect(result.stderrHead == "err")
        #expect(result.stderrTail == "err")
        let failing = IndexerProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "yes error-line | head -c 200000 1>&2; exit 3"], directory: URL(filePath: "/tmp"), environment: [:])
        let failure = try await failing.run()
        #expect(failure.exitStatus == 3)
        #expect(!failure.succeeded)
        #expect(failure.stderrTail.utf8.count <= IndexerProcess.tailLimit + 4)
        #expect(failure.stderrTail.hasPrefix("…"))
        #expect(failure.stderrHead.hasPrefix("error-line"))
        #expect(failure.stderrHead.utf8.count <= IndexerProcess.tailLimit + 4)
        let missing = IndexerProcess(executable: URL(filePath: "/nonexistent/tool"), arguments: [], directory: URL(filePath: "/tmp"), environment: [:])
        await #expect(throws: BrowserError.self) { try await missing.run() }
    }

    @Test @MainActor func queuedCompilerProgressCannotReplaceFinishedStatus() async throws {
        let root = try Self.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let fake = FakeIndexer(id: "fake", displayName: "Noisy compiler",
            script: "i=0; while [ $i -lt 2000 ]; do echo progress-$i; i=$((i + 1)); done; cp '\(Self.fixtureIndex.path)' \"$1\"",
            marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: root.appending(path: "cache")))
        let sink = PublicationSink()
        await service.open(Self.snapshot(root)) { await sink.receive($0) }
        try await Self.waitUntil { sink.publications.contains { $0.status == .current } }
        // Drain tasks queued by the process's final output after it exited.
        try await Task.sleep(for: .milliseconds(200))
        let completed = try #require(sink.publications.firstIndex { $0.status == .current })
        #expect(sink.publications[completed...].allSatisfy { !$0.status.isIndexing })
        #expect(sink.latest?.outcomes.first?.result == .generated)
        await service.close()
    }

    @Test func cancellationTerminatesTheWholeProcessGroup() async throws {
        let marker = "radiology-group-\(UUID().uuidString)"
        let process = IndexerProcess(executable: URL(filePath: "/bin/sh"), arguments: ["-c", "sleep 300 & sleep 300; echo \(marker)"], directory: URL(filePath: "/tmp"), environment: ["RADIOLOGY_MARKER": marker])
        let task = Task { try await process.run() }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        try await Task.sleep(for: .milliseconds(300))
        // Both the shell and its background `sleep` must be gone.
        let check = Process()
        check.executableURL = URL(filePath: "/bin/sh")
        check.arguments = ["-c", "ps -axo command | grep -c '[s]leep 300' || true"]
        let pipe = Pipe()
        check.standardOutput = pipe
        try check.run()
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        check.waitUntilExit()
        let count = Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        #expect(count == 0, "orphaned sleep processes remain: \(count)")
    }

    @Test func generatesCachesReloadsAndDetectsStaleness() async throws {
        let root = try Self.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let fake = FakeIndexer(id: "fake", displayName: "Fake", script: "cp '\(Self.fixtureIndex.path)' \"$1\"", marker: "Cargo.toml", installable: true)
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot.appending(path: "tools")))
        let sink = PublicationSink()
        await service.open(Self.snapshot(root)) { publication in await sink.receive(publication) }
        try await Self.waitUntil { sink.latest?.status == .current }
        let first = try #require(await sink.latest)
        #expect(first.index.documentCount == 2)
        #expect(first.outcomes.first?.result == .generated)
        #expect(first.outcomes.first?.indexerVersion == "fake 1.0")
        #expect(first.outcomes.first?.commandLine.map { $0.contains("/bin/sh -c") } == true)
        #expect(await sink.publications.contains { $0.status.isIndexing })
        // Generated data lives in the cache directory, never in the repository.
        let cacheDirectory = IndexCache(root: cacheRoot).directory(for: root)
        #expect(FileManager.default.fileExists(atPath: cacheDirectory.appending(path: "index-metadata.json").path))
        #expect(FileManager.default.fileExists(atPath: cacheDirectory.appending(path: "fake.scip").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "index.scip").path))
        let metadata = try #require(IndexCache(root: cacheRoot).loadMetadata(for: root))
        #expect(metadata.strategies.first?.indexerVersion == "fake 1.0")
        #expect(metadata.headCommit == nil, "a Git-free folder has no commit")

        // A second open with nothing changed must load the cache and stop at Current without running the tool.
        let failing = FakeIndexer(id: "fake", displayName: "Fake", script: "exit 9", marker: "Cargo.toml", installable: true)
        let second = SemanticIndexService(indexers: [failing], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot.appending(path: "tools")))
        let secondSink = PublicationSink()
        await second.open(Self.snapshot(root)) { publication in await secondSink.receive(publication) }
        try await Self.waitUntil { secondSink.latest?.status == .current }
        #expect(await secondSink.latest?.outcomes.first?.result == .cached(stale: false))
        #expect(await secondSink.latest?.index.documentCount == 2)

        // Touch a source file: the cache is served as Possibly Stale, then regeneration fails and is reported in full.
        try await Task.sleep(for: .milliseconds(1100))
        try Data("pub struct Circle { pub radius: f64 }\n".utf8).write(to: root.appending(path: "src/shapes.rs"))
        let third = SemanticIndexService(indexers: [failing], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot.appending(path: "tools")))
        let thirdSink = PublicationSink()
        await third.open(Self.snapshot(root)) { publication in await thirdSink.receive(publication) }
        try await Self.waitUntil { if case .partial = thirdSink.latest?.status { true } else { false } }
        let stale = await thirdSink.publications.first { if case .possiblyStale = $0.status { true } else { false } }
        #expect(stale != nil, "the stale cache is published before regeneration")
        #expect(stale?.index.documentCount == 2)
        guard case .failed(let failure)? = await thirdSink.latest?.outcomes.first?.result else { return }
        #expect(failure.kind == .processFailed)
        #expect(failure.exitStatus == 9)
        #expect(failure.indexerName == "Fake")
        #expect(failure.commandLine?.contains("exit 9") == true)
        #expect(await thirdSink.latest?.index.documentCount == 2, "the previous index stays usable after a failed refresh")
    }

    @Test func missingToolsAndCancellationAreReportedNotHidden() async throws {
        let root = try Self.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let missing = FakeIndexer(id: "fake", displayName: "Fake", script: "exit 0", marker: "Cargo.toml", installable: false)
        let service = SemanticIndexService(indexers: [missing], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot))
        let sink = PublicationSink()
        await service.open(Self.snapshot(root)) { publication in await sink.receive(publication) }
        try await Self.waitUntil { if case .failed = sink.latest?.status { true } else { false } }
        guard case .failed(let failure)? = await sink.latest?.status else { return }
        #expect(failure.kind == .toolMissing(canInstall: false))
        #expect(failure.message.contains("Install the fake tool."))

        let slow = FakeIndexer(id: "slow", displayName: "Slow", script: "sleep 300 & wait", marker: "Cargo.toml", installable: true)
        let slowService = SemanticIndexService(indexers: [slow], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot))
        let slowSink = PublicationSink()
        await slowService.open(Self.snapshot(root)) { publication in await slowSink.receive(publication) }
        try await Self.waitUntil { if case .indexing(let progress)? = slowSink.latest?.status { progress.phase == .indexing } else { false } }
        await slowService.cancel()
        try await Self.waitUntil { slowSink.latest?.status == .noIndex(reason: "Indexing was cancelled.") }
        #expect(await slowSink.latest?.outcomes.first?.result == .cancelled)

        // A superseding open must stop the old run from publishing into the new repository.
        let other = try Self.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: other) }
        let supersede = SemanticIndexService(indexers: [slow], cache: IndexCache(root: cacheRoot), tools: ToolDirectory(url: cacheRoot))
        let supersedeSink = PublicationSink()
        await supersede.open(Self.snapshot(root)) { publication in await supersedeSink.receive(publication) }
        try await Self.waitUntil { if case .indexing(let progress)? = supersedeSink.latest?.status { progress.phase == .indexing } else { false } }
        let otherSink = PublicationSink()
        await supersede.open(Self.snapshot(other)) { publication in await otherSink.receive(publication) }
        try await Self.waitUntil { if case .indexing(let progress)? = otherSink.latest?.status { progress.phase == .indexing } else { false } }
        try await Task.sleep(for: .milliseconds(500))
        #expect(await supersedeSink.publications.allSatisfy { $0.repositoryRoot == root })
        #expect(await otherSink.publications.allSatisfy { $0.repositoryRoot == other })
        await supersede.close()
    }

    @Test func nestedProjectsPrefixDocumentPaths() throws {
        let data = try Data(contentsOf: Self.fixtureIndex)
        let raw = try SCIPDecoder.decode(data)
        let index = SemanticIndex(inputs: [SemanticIndex.Input(index: raw, projectDirectory: "engine/rust")])
        #expect(index.documents.keys.sorted() == ["engine/rust/src/lib.rs", "engine/rust/src/shapes.rs"])
        let circle = SemanticSymbolID(symbol: "rust-analyzer cargo ra_fixture 0.1.0 shapes/Circle#", document: "")
        #expect(index.definitions(of: circle).first?.path == "engine/rust/src/shapes.rs")
    }

    @Test func inspectionPicksTopLevelProjectsAndRegistryStrategies() {
        let inspection = RepositoryInspection(root: URL(filePath: "/tmp/x"), paths: [
            "Cargo.toml", "src/main.rs", "crates/a/Cargo.toml", "crates/a/src/lib.rs",
            "web/package.json", "web/tsconfig.json", "web/src/index.ts",
            "tools/go.mod", "tools/main.go", "scripts/setup.py", "scripts/run.py", "docs/readme.md", "native/compile_commands.json",
        ], isGit: true)
        #expect(inspection.topLevelDirectories(containing: "Cargo.toml") == [""])
        let strategies = SemanticIndexerRegistry.strategies(for: inspection).selected
        #expect(strategies.map(\.id) == ["rust-analyzer", "scip-clang", "scip-go@tools", "scip-typescript@web", "scip-python@scripts"], "root projects first, then by depth in registry order")
        #expect(strategies.first { $0.indexerID == "scip-typescript" }?.evidence == ["web/tsconfig.json"])
        #expect(SemanticIndexService.unsupportedLanguages(in: inspection, covered: strategies).isEmpty)
        let swiftOnly = RepositoryInspection(root: URL(filePath: "/tmp/y"), paths: ["Package.swift", "Sources/A.swift", "Sources/B.kt"], isGit: false)
        #expect(SemanticIndexerRegistry.strategies(for: swiftOnly).selected.isEmpty)
        #expect(SemanticIndexService.unsupportedLanguages(in: swiftOnly, covered: []) == ["Kotlin", "Swift"])
    }

    @Test func substantialMonoreposDoNotSilentlyDropLaterRustProjects() {
        var paths: [String] = []
        for index in 0..<12 {
            paths += ["modules/project\(index)/Cargo.toml", "modules/project\(index)/src/lib.rs"]
        }
        let inspection = RepositoryInspection(root: URL(filePath: "/tmp/large-rust"), paths: paths, isGit: true)
        let plan = SemanticIndexerRegistry.strategies(for: inspection)
        #expect(plan.selected.count == 12)
        #expect(plan.skipped.isEmpty)
        #expect(plan.selected.contains { $0.projectDirectory == "modules/project11" })
    }

    @Test func rustAnalyzerConfigurationUsesRealManifestFeaturesAsCfgOverrides() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let toolsURL = root.appending(path: "tools", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "src"), withIntermediateDirectories: true)
        try Data("[package]\nname='fixture'\nversion='0.1.0'\n[features]\ndefault=[]\napp-runtime=[]\nembedding_gate=[]\n".utf8)
            .write(to: root.appending(path: "Cargo.toml"))
        try Data("pub fn run() {}\n".utf8).write(to: root.appending(path: "src/lib.rs"))
        let inspection = RepositoryInspection(root: root, paths: ["Cargo.toml", "src/lib.rs"], isGit: false)
        let strategy = try #require(RustAnalyzerIndexer().strategies(for: inspection).first)
        let command = RustAnalyzerIndexer().command(for: strategy, inspection: inspection,
                                                     executable: URL(filePath: "/bin/echo"),
                                                     output: root.appending(path: "index.scip"),
                                                     tools: ToolDirectory(url: toolsURL))
        let configIndex = try #require(command.arguments.firstIndex(of: "--config-path"))
        let config = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: command.arguments[configIndex + 1]))) as? [String: Any]
        let cargo = try #require(config?["cargo"] as? [String: Any])
        #expect(cargo["features"] as? String == "all")
        let cfgs = try #require(cargo["cfgs"] as? [String])
        #expect(cfgs == ["debug_assertions", "miri", "feature=app-runtime", "feature=embedding_gate"])
    }

    /// Real generation: rust-analyzer indexes a copy of the fixture crate that
    /// carries no prebuilt data. Skipped when rust-analyzer cannot run here.
    @Test func realRustAnalyzerGeneratesAnIndexFromScratch() async throws {
        let provisioner = ToolProvisioner(tools: .default)
        guard case .available(_, let version) = await provisioner.availability(of: RustAnalyzerIndexer()) else {
            print("rust-analyzer unavailable; skipping real generation test")
            return
        }
        let root = try Self.temporaryRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheRoot = FileManager.default.temporaryDirectory.appending(path: "radiology-cache-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: cacheRoot) }
        let service = SemanticIndexService(indexers: [RustAnalyzerIndexer()], cache: IndexCache(root: cacheRoot), tools: .default)
        let sink = PublicationSink()
        await service.open(Self.snapshot(root)) { publication in await sink.receive(publication) }
        try await Self.waitUntil(.seconds(180)) { sink.latest?.status == .current || { if case .failed = sink.latest?.status { true } else { false } }() }
        let publication = try #require(await sink.latest)
        if case .failed(let failure) = publication.status {
            Issue.record("rust-analyzer failed: \(failure.message)\n\(failure.stderr)")
            return
        }
        #expect(publication.outcomes.first?.indexerVersion == version)
        #expect(publication.index.documentCount == 2)
        let lib = try SourceBuffer(path: "src/lib.rs", data: Data(contentsOf: root.appending(path: "src/lib.rs")))
        let semantics = DocumentSemantics.make(document: publication.index.documents["src/lib.rs"]!, buffer: lib)
        let target = publication.index.target(in: semantics, at: lib.byteOffset(line: 5, column: 28))
        #expect(target?.displayName == "Circle")
        #expect(target?.definitions.first?.path == "src/shapes.rs")
    }
}
