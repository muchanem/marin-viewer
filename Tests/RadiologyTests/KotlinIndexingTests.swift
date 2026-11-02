import Foundation
import Testing
@testable import Radiology

struct KotlinIndexingTests {
    static let fixtureRoot = Bundle.module.resourceURL!.appending(path: "Fixtures/scip-kotlin")
    static let readerPath = "src/main/kotlin/Reader.kt"
    static let storePath = "src/main/kotlin/Store.kt"

    static func buffer(_ path: String) throws -> SourceBuffer {
        try SourceBuffer(path: path, data: Data(contentsOf: fixtureRoot.appending(path: path)))
    }

    static func index() throws -> SemanticIndex {
        SemanticIndex(inputs: [.init(index: try SCIPDecoder.decode(Data(contentsOf: fixtureRoot.appending(path: "index.scip"))),
                                    defaultEncoding: ScipKotlinIndexer().defaultEncoding)])
    }

    @Test func realCompilerIndexPreservesOverloadsAndUTF16AfterEmoji() async throws {
        let index = try Self.index()
        let reader = try Self.buffer(Self.readerPath)
        let semantics = DocumentSemantics.make(document: try #require(index.documents[reader.path]), buffer: reader)
        #expect(index.documents[reader.path]?.encoding == .utf16)
        #expect(semantics.unmappedCount == 0)
        let integerCall = (reader.text as NSString).range(of: "read(2)").location
        let stringCall = (reader.text as NSString).range(of: "read(\"name\")").location
        let integer = try #require(index.target(in: semantics, at: reader.byteOffset(forUTF16: integerCall + 1)))
        let string = try #require(index.target(in: semantics, at: reader.byteOffset(forUTF16: stringCall + 1)))
        #expect(integer.displayName == "read" && string.displayName == "read")
        #expect(integer.symbol != string.symbol, "overloads cannot share references merely because their spelling matches")
        #expect(integer.definitions.first?.path == Self.storePath && integer.definitions.first?.range.startLine == 3)
        #expect(string.definitions.first?.path == Self.storePath && string.definitions.first?.range.startLine == 4)
        let worker = SemanticQueryWorker()
        let references = try await worker.references(of: integer.symbol, in: index, root: Self.fixtureRoot)
        #expect(references.referenceCount == 1)
        #expect(references.groups.first { $0.path == Self.readerPath }?.hits.first?.match == "read")
        #expect(!references.groups.contains { $0.path.contains("Noise") })
        #expect(references.unmappedCount == 0 && references.unreadablePaths.isEmpty)
    }

    @Test func strategyUsesWholeGradleBuildAndDoesNotInventProjectsFromKotlinFiles() {
        let indexer = ScipKotlinIndexer()
        let root = URL(filePath: "/tmp/example")
        let inspection = RepositoryInspection(root: root, paths: ["settings.gradle.kts", "build.gradle.kts",
            "modules/contacts/build.gradle.kts", "modules/contacts/src/main/Contacts.kt", "core/src/main/Core.kt",
            "tools/independent/settings.gradle.kts", "tools/independent/src/Main.kt"], isGit: true)
        let strategies = indexer.strategies(for: inspection)
        #expect(strategies.count == 1 && strategies.first?.projectDirectory == "")
        #expect(strategies.first?.languages == ["Kotlin", "Java"])
        #expect(strategies.first?.evidence == ["build.gradle.kts", "settings.gradle.kts"])
        #expect(indexer.strategies(for: RepositoryInspection(root: root, paths: ["Contacts.kt"], isGit: false)).isEmpty)
        #expect(indexer.strategies(for: RepositoryInspection(root: root, paths: ["build.gradle.kts"], isGit: false)).isEmpty)
        #expect(SemanticIndexerRegistry.extensions(for: ["Kotlin", "Java"]) == ["kt", "java"])
        #expect(indexer.requiresIsolatedWorkspace)
    }

    @Test @MainActor func cacheAndReuseRetainUTF16ColumnsAndPartialCompilerCoverage() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-kotlin-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        func copyInputs(_ name: String) throws -> URL {
            let root = directory.appending(path: name)
            for path in ["build.gradle.kts", "settings.gradle.kts", Self.readerPath, Self.storePath] {
                try GitFixture.write(String(contentsOf: Self.fixtureRoot.appending(path: path), encoding: .utf8), to: root.appending(path: path))
            }
            return root
        }
        let root = try copyInputs("original")
        let copy = try copyInputs("copy")
        let snapshot = try await RepositoryWorker().open(root)
        let copiedSnapshot = try await RepositoryWorker().open(copy)
        let tools = ToolDirectory(url: directory.appending(path: "tools"))
        let cache = IndexCache(root: directory.appending(path: "cache"))
        let generated = FakeIndexer(id: "scip-kotlin", displayName: "Kotlin fixture", defaultEncoding: .utf16,
                                    script: "cp '\(Self.fixtureRoot.appending(path: "index.scip").path)' \"$1\"; echo RADIOLOGY_KOTLIN_PARTIAL_BUILD >&2",
                                    marker: "build.gradle.kts", installable: true, languages: ["Kotlin"])
        let service = SemanticIndexService(indexers: [generated], cache: cache, tools: tools)
        let sink = PublicationSink()
        await service.open(snapshot) { await sink.receive($0) }
        try await IndexingTests.waitUntil { if case .partial = sink.latest?.status { true } else { false } }
        #expect(sink.latest?.outcomes.first?.capability == .partialBuild)
        #expect(sink.latest?.index.documents["src/main/kotlin/Noise.kt"] == nil, "compiler-only documents outside the snapshot are not navigable")
        #expect(sink.latest?.outcomes.first?.documentCount == 2)

        // A cache hit or exact-byte reuse must succeed without running this.
        let failing = FakeIndexer(id: generated.id, displayName: generated.displayName, defaultEncoding: .utf16,
                                  script: "exit 99", marker: generated.marker, installable: true, languages: ["Kotlin"])
        let reloaded = SemanticIndexService(indexers: [failing], cache: cache, tools: tools)
        let reloadSink = PublicationSink()
        await reloaded.open(snapshot) { await reloadSink.receive($0) }
        try await IndexingTests.waitUntil { if case .partial = reloadSink.latest?.status { true } else { false } }
        #expect(reloadSink.latest?.outcomes.first?.result == .cached(stale: false))
        #expect(reloadSink.latest?.outcomes.first?.capability == .partialBuild)
        #expect(reloadSink.latest?.index.documents[Self.readerPath]?.encoding == .utf16)
        #expect(reloadSink.latest?.index.documents["src/main/kotlin/Noise.kt"] == nil)

        let reused = SemanticIndexService(indexers: [failing], cache: IndexCache(root: directory.appending(path: "copy-cache")), tools: tools)
        let reuseSink = PublicationSink()
        await reused.open(copiedSnapshot, options: IndexOpenOptions(reuseSources: [IndexReuseSource(cache: cache, root: root, label: "original")])) {
            await reuseSink.receive($0)
        }
        try await IndexingTests.waitUntil { if case .partial = reuseSink.latest?.status { true } else { false } }
        #expect(reuseSink.latest?.outcomes.first?.result == .reused(from: "original"))
        #expect(reuseSink.latest?.outcomes.first?.capability == .partialBuild)
        let index = try #require(reuseSink.latest?.index)
        #expect(index.documents["src/main/kotlin/Noise.kt"] == nil)
        let buffer = try Self.buffer(Self.readerPath)
        let document = try #require(index.documents[buffer.path])
        let mapped = DocumentSemantics.make(document: document, buffer: buffer)
        let read = (buffer.text as NSString).range(of: "read(2)").location
        #expect(index.target(in: mapped, at: buffer.byteOffset(forUTF16: read + 1))?.displayName == "read")
    }

    @Test func isolatedInputsPreserveBytesModesAndNeverWriteThroughSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-isolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appending(path: "original")
        try GitFixture.write("original", to: original.appending(path: "src/Main.kt"))
        try GitFixture.write("#!/bin/sh\n", to: original.appending(path: "gradlew"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: original.appending(path: "gradlew").path)
        try FileManager.default.createSymbolicLink(at: original.appending(path: "Alias.kt"), withDestinationURL: original.appending(path: "src/Main.kt"))
        let inspection = RepositoryInspection(root: original, paths: ["src/Main.kt", "gradlew", "Alias.kt"], isGit: false)
        let workspace = try IndexingWorkspace.make(inspection: inspection, parent: directory.appending(path: "cache"))
        defer { workspace.remove() }
        #expect(try Data(contentsOf: workspace.root.appending(path: "src/Main.kt")) == Data("original".utf8))
        #expect(FileManager.default.isExecutableFile(atPath: workspace.root.appending(path: "gradlew").path))
        try workspace.verifyInputs()
        #expect(try workspace.root.appending(path: "Alias.kt").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        #expect(workspace.root.appending(path: "Alias.kt").resolvingSymlinksInPath().path.hasPrefix(workspace.root.path + "/"))
        try Data("compiled copy".utf8).write(to: workspace.root.appending(path: "Alias.kt"))
        #expect(throws: BrowserError.self) { try workspace.verifyInputs() }
        #expect(try String(contentsOf: original.appending(path: "src/Main.kt"), encoding: .utf8) == "original")
        #expect(workspace.inspection(from: inspection).paths == inspection.paths)
        var stale = inspection
        stale.blobIDs = ["src/Main.kt": ContentDigest.blobID(of: Data("older".utf8))]
        #expect(throws: BrowserError.self) { try IndexingWorkspace.make(inspection: stale, parent: directory.appending(path: "cache")) }
        #expect(throws: BrowserError.self) { try IndexingWorkspace.make(inspection: RepositoryInspection(root: original, paths: ["../escape"], isGit: false), parent: directory.appending(path: "cache")) }
        try FileManager.default.createSymbolicLink(at: original.appending(path: "External.kt"), withDestinationURL: directory.appending(path: "outside.kt"))
        try GitFixture.write("outside", to: directory.appending(path: "outside.kt"))
        #expect(throws: BrowserError.self) { try IndexingWorkspace.make(inspection: RepositoryInspection(root: original, paths: ["External.kt"], isGit: false), parent: directory.appending(path: "cache")) }
    }

    @Test func directoryLinksAreRebasedAndTrackedBuildInputsSurviveBrowserFiltering() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-directory-link-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appending(path: "original")
        let target = ".claude/skills/harness-development/SKILL.md"
        let link = ".agents/skills/harness-development"
        let vendor = "vendor/dependency/src/Main.kt"
        try GitFixture.write("instructions", to: original.appending(path: target))
        try GitFixture.write("dependency", to: original.appending(path: vendor))
        try FileManager.default.createDirectory(at: original.appending(path: ".agents/skills"), withIntermediateDirectories: true)
        let relative = "../../.claude/skills/harness-development"
        try FileManager.default.createSymbolicLink(atPath: original.appending(path: link).path, withDestinationPath: relative)
        // Also cover an absolute internal directory link, whose target must
        // never keep pointing into the original checkout.
        try FileManager.default.createSymbolicLink(at: original.appending(path: "Absolute"), withDestinationURL: original.appending(path: ".claude/skills/harness-development"))
        try FileManager.default.createSymbolicLink(atPath: original.appending(path: "AGENTS.md").path, withDestinationPath: "../missing.md")
        try FileManager.default.createSymbolicLink(atPath: original.appending(path: "InternalMissing").path, withDestinationPath: "missing/directory")
        let ids = ContentDigest.workingTreeBlobIDs(root: original, paths: [target, link, vendor, "Absolute", "AGENTS.md", "InternalMissing"])
        #expect(ids[link] == ContentDigest.blobID(of: Data(relative.utf8)))
        let inspection = RepositoryInspection(root: original, paths: [link], isGit: true, blobIDs: ids)
        let workspace = try IndexingWorkspace.make(inspection: inspection, parent: directory.appending(path: "cache"))
        defer { workspace.remove() }
        try workspace.verifyInputs()
        #expect(try String(contentsOf: workspace.root.appending(path: "AGENTS.md"), encoding: .utf8) == "../missing.md")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: workspace.root.appending(path: "InternalMissing").path).hasPrefix(workspace.root.path + "/"))
        #expect(try String(contentsOf: workspace.root.appending(path: vendor), encoding: .utf8) == "dependency")
        for alias in [link, "Absolute"] {
            let resolved = workspace.root.appending(path: alias).resolvingSymlinksInPath()
            #expect(resolved.path.hasPrefix(workspace.root.path + "/"))
            #expect(try String(contentsOf: resolved.appending(path: "SKILL.md"), encoding: .utf8) == "instructions")
        }
        try Data("build changed copy".utf8).write(to: workspace.root.appending(path: link + "/SKILL.md"))
        #expect(try String(contentsOf: original.appending(path: target), encoding: .utf8) == "instructions")
        #expect(throws: BrowserError.self) { try workspace.verifyInputs() }
    }

    @Test @MainActor func workingTreeServiceCopiesTrackedDependenciesAndInvalidatesTheirCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-working-inputs-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appending(path: "original")
        for path in ["build.gradle.kts", "settings.gradle.kts", Self.readerPath, Self.storePath] {
            try GitFixture.write(String(contentsOf: Self.fixtureRoot.appending(path: path), encoding: .utf8), to: root.appending(path: path))
        }
        let dependency = "vendor/dependency/input.txt"
        try GitFixture.write("first", to: root.appending(path: dependency))
        try await Task.detached {
            try GitFixture.run(["init", "-q"], in: root)
            try GitFixture.run(["add", "-A"], in: root)
            try GitFixture.run(["commit", "-q", "-m", "compiler inputs"], in: root)
        }.value
        let snapshot = try await RepositoryWorker().open(root)
        #expect(!snapshot.files.contains { $0.path == dependency }, "the file-browser inventory intentionally excludes vendor")
        let cache = IndexCache(root: directory.appending(path: "cache"))
        let marker = directory.appending(path: "ran")
        let fake = FakeIndexer(id: "scip-kotlin", displayName: "Isolated Kotlin fixture", defaultEncoding: .utf16,
                              script: "test -f vendor/dependency/input.txt || exit 31; cp '\(Self.fixtureRoot.appending(path: "index.scip").path)' \"$1\"; echo ran >> '\(marker.path)'",
                              marker: "build.gradle.kts", installable: true, languages: ["Kotlin"], requiresIsolatedWorkspace: true)
        let tools = ToolDirectory(url: directory.appending(path: "tools"))
        let generated = SemanticIndexService(indexers: [fake], cache: cache, tools: tools)
        let first = PublicationSink()
        await generated.open(snapshot) { await first.receive($0) }
        try await IndexingTests.waitUntil { first.latest?.status == .current }
        #expect(first.latest?.outcomes.first?.result == .generated)
        #expect(first.latest?.index.documents[Self.readerPath]?.encoding == .utf16)
        await generated.close()
        // Only a tracked dependency excluded from the file browser changes.
        // A reader-based fingerprint would incorrectly keep the old cache.
        try GitFixture.write("second version", to: root.appending(path: dependency))
        let refreshed = SemanticIndexService(indexers: [fake], cache: cache, tools: tools)
        let second = PublicationSink()
        await refreshed.open(snapshot) { await second.receive($0) }
        try await IndexingTests.waitUntil { second.latest?.status == .current }
        #expect(second.latest?.outcomes.first?.result == .generated)
        #expect(try String(contentsOf: marker, encoding: .utf8).split(separator: "\n").count == 2)
        #expect(try String(contentsOf: root.appending(path: dependency), encoding: .utf8) == "second version")
        await refreshed.close()
    }
}
