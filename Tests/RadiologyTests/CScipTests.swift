import Foundation
import Testing
@testable import Radiology

@Suite(.serialized)
struct CScipTests {
    static var fixtureRoot: URL { Bundle.module.resourceURL!.appending(path: "Fixtures/scip-clang") }

    static func fixtureIndex() throws -> SemanticIndex {
        let raw = try SCIPDecoder.decode(Data(contentsOf: fixtureRoot.appending(path: "index.scip")))
        #expect(raw.metadata.toolName == "scip-clang")
        #expect(raw.documents.map(\.relativePath).sorted() == ["src/math.c", "src/math.h", "src/reader.c", "src/reader.cpp"])
        return SemanticIndex(inputs: [.init(index: raw, defaultEncoding: .utf8)])
    }

    @Test func realCompilerIndexResolvesCAndCppOverloadsAfterUnicode() throws {
        let index = try Self.fixtureIndex()
        let buffer = try SourceBuffer(path: "src/reader.cpp", data: Data(contentsOf: Self.fixtureRoot.appending(path: "src/reader.cpp")))
        let document = try #require(index.documents[buffer.path])
        #expect(document.encoding == .utf8)
        let semantics = DocumentSemantics.make(document: document, buffer: buffer)
        #expect(semantics.unmappedCount == 0)
        func target(_ text: String) throws -> SemanticTarget {
            let offset = try #require(buffer.text.range(of: text))
            let byte = buffer.text.utf8.distance(from: buffer.text.utf8.startIndex, to: offset.lowerBound)
            let found = index.target(in: semantics, at: byte + 1)
            return try #require(found, "Missing compiler occurrence for \(text)")
        }
        let single = try target("render(4)")
        let pair = try target("render(4, 5)")
        #expect(single.symbol != pair.symbol)
        #expect(single.displayName == "render")
        #expect(pair.displayName == "render")
        #expect(single.definitions.contains { $0.path == "src/reader.cpp" && $0.range.startLine == 1 })
        #expect(pair.definitions.contains { $0.path == "src/reader.cpp" && $0.range.startLine == 4 })
        let cBuffer = try SourceBuffer(path: "src/reader.c", data: Data(contentsOf: Self.fixtureRoot.appending(path: "src/reader.c")))
        let cSemantics = DocumentSemantics.make(document: try #require(index.documents[cBuffer.path]), buffer: cBuffer)
        let call = (cBuffer.text as NSString).range(of: "add(left").location
        let add = try #require(index.target(in: cSemantics, at: cBuffer.byteOffset(forUTF16: call + 1)))
        #expect(add.displayName == "add")
        #expect(add.definitions.contains { $0.path == "src/math.c" })
        #expect(index.referenceCount(of: add.symbol) == 2, "the C header declaration and C call are references")
        // Upstream 0.4.0 omits LinkageSpecDecl symbols in extern "C" blocks.
        // Preserve that gap: never guess the missing C++-to-C call by name.
        let missing = (buffer.text as NSString).range(of: "add(value").location
        #expect(index.target(in: semantics, at: buffer.byteOffset(forUTF16: missing + 1)) == nil)
    }

    @Test func compilationDatabaseDiscoveryIncludesHiddenBuildOutputsAndPinsSnapshots() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-compdb-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try GitFixture.write("[]", to: root.appending(path: "build/compile_commands.json"))
        try GitFixture.write("[]", to: root.appending(path: "native/cmake-build-debug/compile_commands.json"))
        let inspection = RepositoryInspection(root: root, paths: ["native/CMakeLists.txt", "src/a.cpp"], isGit: true)
        let expanded = CompilationDatabaseDiscovery.addingDatabases(to: inspection)
        #expect(expanded.paths.contains("build/compile_commands.json"))
        #expect(expanded.paths.contains("native/cmake-build-debug/compile_commands.json"))
        #expect(ScipClangIndexer().strategies(for: expanded).first?.evidence == ["build/compile_commands.json"])
        var pinned = inspection
        pinned.blobIDs = ["native/CMakeLists.txt": "blob"]
        #expect(CompilationDatabaseDiscovery.addingDatabases(to: pinned).paths == inspection.paths)
        #expect(!SemanticIndexService.clangBuildHint(in: inspection, covered: []).isEmpty)
        #expect(SemanticIndexService.clangBuildHint(in: expanded, covered: ScipClangIndexer().strategies(for: expanded)).isEmpty)
    }

    @Test func clangErrorsRemainPartialEvenWhenTheProcessSucceeds() {
        #expect(!SemanticIndexService.clangReportedErrors("Finished indexing 2 translation units (num errored TUs: 0)."))
        #expect(SemanticIndexService.clangReportedErrors("Finished indexing 2 translation units (num errored TUs: 1)."))
        #expect(SemanticIndexService.clangReportedErrors("src/reader.cpp:3: error: missing header"))
        #expect(!SemanticIndexService.clangReportedErrors("warning: unused option"))
    }

    @Test @MainActor func realClangServiceDiscoversBuildDatabaseCachesCoverageAndLeavesSourcesUntouched() async throws {
        let tools = ToolDirectory.default
        guard ScipClangIndexer().locate(in: tools) != nil, ToolLocator.executable("clang") != nil else { return }
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-real-clang-\(UUID().uuidString)").resolvingSymlinksInPath()
        let root = directory.appending(path: "repository")
        defer { try? FileManager.default.removeItem(at: directory) }
        for path in ["src/math.h", "src/math.c", "src/reader.c", "src/reader.cpp"] {
            try GitFixture.write(String(contentsOf: Self.fixtureRoot.appending(path: path), encoding: .utf8), to: root.appending(path: path))
        }
        try GitFixture.write("int unused() { return 1; }\n", to: root.appending(path: "src/unused.cpp"))
        var database: [[String: Any]] = []
        for (name, standard) in [("math.c", "c11"), ("reader.c", "c11"), ("reader.cpp", "c++20")] {
            let path = "src/" + name
            let arguments = ["/usr/bin/clang", "-std=" + standard, "-Isrc", "-c", path, "-o", directory.appending(path: name + ".o").path]
            database.append(["directory": root.path, "file": path, "arguments": arguments])
        }
        try FileManager.default.createDirectory(at: root.appending(path: "build"), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: database).write(to: root.appending(path: "build/compile_commands.json"))
        let snapshot = try await RepositoryWorker().open(root)
        #expect(!snapshot.files.contains { $0.path == "build/compile_commands.json" })
        let paths = snapshot.files.map(\.path) + ["build/compile_commands.json"]
        let original = ContentDigest.workingTreeBlobIDs(root: root, paths: paths)
        let cache = IndexCache(root: directory.appending(path: "cache"))
        let service = SemanticIndexService(indexers: [ScipClangIndexer()], cache: cache, tools: tools)
        let sink = PublicationSink()
        await service.open(snapshot) { await sink.receive($0) }
        try await IndexingTests.waitUntil { sink.latest?.status.isIndexing == false }
        let publication = try #require(sink.latest)
        #expect(publication.index.documents.count == 4)
        #expect(publication.outcomes.first?.strategy.evidence == ["build/compile_commands.json"])
        #expect(publication.outcomes.first?.result == .generated)
        #expect(publication.outcomes.first?.capability == .partialBuild)
        #expect(publication.outcomes.first?.missingFiles.map(\.path) == ["src/unused.cpp"])
        if case .partial = publication.status {} else { Issue.record("Expected partial C++ coverage: \(publication.status)") }
        #expect(ContentDigest.workingTreeBlobIDs(root: root, paths: paths) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "scip-clang-supplementary-output").path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "index.scip").path))
        await service.close()
        let reloaded = SemanticIndexService(indexers: [ScipClangIndexer()], cache: cache, tools: tools)
        let reloadSink = PublicationSink()
        await reloaded.open(snapshot) { await reloadSink.receive($0) }
        try await IndexingTests.waitUntil { reloadSink.latest?.status.isIndexing == false }
        #expect(reloadSink.latest?.outcomes.first?.result == .cached(stale: false))
        #expect(reloadSink.latest?.outcomes.first?.capability == .partialBuild)
        #expect(reloadSink.latest?.index.documents["src/reader.cpp"]?.encoding == .utf8)
        // Removing the real database switches to honest source-only defaults.
        try FileManager.default.removeItem(at: root.appending(path: "build/compile_commands.json"))
        await reloaded.reindex()
        try await IndexingTests.waitUntil { reloadSink.latest?.outcomes.first?.capability == .bestEffort && reloadSink.latest?.status.isIndexing == false }
        #expect(reloadSink.latest?.outcomes.first?.strategy.evidence == [ClangFallbackDatabase.marker])
        #expect(reloadSink.latest?.index.documents.count == 5)
        try JSONSerialization.data(withJSONObject: database).write(to: root.appending(path: "build/compile_commands.json"))
        await reloaded.reindex()
        try await IndexingTests.waitUntil { reloadSink.latest?.outcomes.first?.capability == .partialBuild && reloadSink.latest?.status.isIndexing == false }
        #expect(reloadSink.latest?.outcomes.first?.strategy.evidence == ["build/compile_commands.json"])
        #expect(reloadSink.latest?.index.documents.count == 4)
        await reloaded.close()
    }

    @Test @MainActor func compilerOutputSupportsReaderDefinitionReferencesAndExactBack() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-cpp-reader-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: Self.fixtureRoot, to: root)
        try GitFixture.write("[]", to: root.appending(path: "compile_commands.json"))
        let fake = FakeIndexer(id: "scip-clang", displayName: "Clang fixture", script: "cp '\(Self.fixtureRoot.appending(path: "index.scip").path)' \"$1\"",
                               marker: "compile_commands.json", installable: true, languages: ["C", "C++"])
        let service = SemanticIndexService(indexers: [fake], cache: IndexCache(root: root.appending(path: "cache")))
        let model = AppModel(preferences: UserDefaults(suiteName: "CScipTests.\(UUID().uuidString)")!, semantics: SemanticModel(service: service))
        model.openRepository(root)
        try await IndexingTests.waitUntil { model.repository != nil && model.semantics.hasIndex && !model.isOpening }
        model.openFile("src/reader.c")
        try await IndexingTests.waitUntil { model.syntax?.path == "src/reader.c" && model.semantics.documentSemantics?.path == "src/reader.c" }
        let buffer = try #require(model.source)
        let call = (buffer.text as NSString).range(of: "add(left").location + 1
        let departure = buffer.location(atByte: buffer.byteOffset(forUTF16: call))
        model.caretMoved(to: departure.byteOffset)
        #expect(model.semantics.caretTarget?.displayName == "add")
        model.findReferencesAtCaret()
        try await IndexingTests.waitUntil { if case .loaded = model.context.references { true } else { false } }
        if case .loaded(let results) = model.context.references { #expect(results.referenceCount == 2) }
        model.goToDefinitionAtCaret()
        try await IndexingTests.waitUntil { model.source?.path == "src/math.c" && !model.isLoadingSource }
        model.goBack()
        try await IndexingTests.waitUntil { model.source?.path == "src/reader.c" && !model.isLoadingSource }
        #expect(model.currentCaretLocation == departure)
        await service.close()
    }
}
