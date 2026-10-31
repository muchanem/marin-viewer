import Foundation
import Testing
@testable import Radiology

@Suite(.serialized)
struct ClangFallbackTests {
    @Test @MainActor func switchingRepositoriesCancelsLargeDefaultPreparationPromptly() async throws {
        guard ScipClangIndexer().locate(in: .default) != nil else { return }
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-clang-cancel-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appending(path: "large")
        var paths: [String] = []
        for index in 0..<1500 {
            let path = "src/file\(index).cpp"
            paths.append(path)
            try GitFixture.write("int function\(index)(int value) { return value + 1; }\n", to: root.appending(path: path))
        }
        let files = paths.map { RepositoryFile(path: $0) }
        let snapshot = RepositorySnapshot(root: root, files: files, tree: FileNode.tree(files: files), isGit: false)
        let other = directory.appending(path: "other")
        try GitFixture.write("readme", to: other.appending(path: "README.md"))
        let otherFiles = [RepositoryFile(path: "README.md")]
        let otherSnapshot = RepositorySnapshot(root: other, files: otherFiles, tree: FileNode.tree(files: otherFiles), isGit: false)
        let cache = IndexCache(root: directory.appending(path: "cache"))
        let service = SemanticIndexService(indexers: [ScipClangIndexer()], cache: cache)
        let oldSink = PublicationSink()
        await service.open(snapshot) { await oldSink.receive($0) }
        try await IndexingTests.waitUntil {
            if case .indexing(let progress) = oldSink.latest?.status { progress.message == "Preparing best-effort C/C++ inputs…" } else { false }
        }
        let started = ContinuousClock.now
        let newSink = PublicationSink()
        await service.open(otherSnapshot) { await newSink.receive($0) }
        try await IndexingTests.waitUntil { if case .noIndex = newSink.latest?.status { true } else { false } }
        #expect(started.duration(to: .now) < .seconds(2))
        try await Task.sleep(for: .milliseconds(100))
        #expect(oldSink.publications.allSatisfy { $0.index.documents.isEmpty })
        #expect(newSink.publications.allSatisfy { $0.repositoryRoot == other })
        #expect(!FileManager.default.fileExists(atPath: cache.indexURL(for: root, strategy: try #require(ScipClangIndexer().strategies(for: RepositoryInspection(root: root, paths: paths, isGit: false)).first)).path))
        await service.close()
    }

    @Test func defaultInputsInferAvailableHeadersAndPreferRealBuilds() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "radiology-clang-defaults-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = ["src/main.cpp", "src/main.c", "src/case.C", "support/include/layout/api.hpp"]
        try GitFixture.write("#include <layout/api.hpp>\nint run() { return api(); }\n", to: root.appending(path: paths[0]))
        try GitFixture.write("int main(void) { return 0; }\n", to: root.appending(path: paths[1]))
        try GitFixture.write("class Reader {};\n", to: root.appending(path: paths[2]))
        try GitFixture.write("int api();\n", to: root.appending(path: paths[3]))
        let inspection = RepositoryInspection(root: root, paths: paths, isGit: false)
        let strategy = try #require(ScipClangIndexer().strategies(for: inspection).first)
        #expect(ClangFallbackDatabase.isFallback(strategy))
        let entries = try ClangFallbackDatabase.entries(for: inspection)
        #expect(entries.map(\.file) == ["src/case.C", "src/main.c", "src/main.cpp"])
        let cpp = try #require(entries.first { $0.file == "src/main.cpp" })
        #expect(cpp.arguments.contains("-std=gnu++20"))
        #expect(cpp.arguments.contains(root.appending(path: "support/include").path))
        #expect(entries.first { $0.file == "src/main.c" }?.arguments.contains("-std=gnu11") == true)
        #expect(entries.first { $0.file == "src/case.C" }?.arguments.contains("-std=gnu++20") == true)
        let configured = RepositoryInspection(root: root, paths: paths + ["compile_commands.json"], isGit: false)
        #expect(ScipClangIndexer().strategies(for: configured).first?.evidence == ["compile_commands.json"])
        let headerOnly = RepositoryInspection(root: root, paths: [paths[3]], isGit: false)
        #expect(try ClangFallbackDatabase.entries(for: headerOnly).map(\.file) == [paths[3]])
        let optionLikePath = "-fplugin=helper.cpp"
        try GitFixture.write("int helper() { return 1; }\n", to: root.appending(path: optionLikePath))
        let unusual = RepositoryInspection(root: root, paths: [optionLikePath], isGit: false)
        #expect(try ClangFallbackDatabase.entries(for: unusual).first?.arguments.last == "./" + optionLikePath)
    }

    @Test @MainActor func noDatabaseStillProducesNavigableCompilerIdentityAndCachedBestEffort() async throws {
        guard ScipClangIndexer().locate(in: .default) != nil else { return }
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-clang-fallback-\(UUID().uuidString)").resolvingSymlinksInPath()
        let root = directory.appending(path: "repository")
        defer { try? FileManager.default.removeItem(at: directory) }
        try GitFixture.write("int increment(int value);\n", to: root.appending(path: "support/include/layout/api.hpp"))
        try GitFixture.write("#include <layout/api.hpp>\nint increment(int value) { return value + 1; }\n", to: root.appending(path: "src/api.cpp"))
        try GitFixture.write("#include <layout/api.hpp>\n#include <missing_header.hpp>\nint run() { return increment(4); }\n", to: root.appending(path: "src/reader.cpp"))
        let snapshot = try await RepositoryWorker().open(root)
        let paths = snapshot.files.map(\.path)
        let original = ContentDigest.workingTreeBlobIDs(root: root, paths: paths)
        let cache = IndexCache(root: directory.appending(path: "cache"))
        let service = SemanticIndexService(indexers: [ScipClangIndexer()], cache: cache)
        let sink = PublicationSink()
        await service.open(snapshot) { await sink.receive($0) }
        try await IndexingTests.waitUntil { sink.latest?.status.isIndexing == false }
        let publication = try #require(sink.latest)
        #expect(publication.outcomes.first?.capability == .bestEffort)
        #expect(publication.outcomes.first?.diagnostics.contains("missing_header.hpp") == true)
        if case .partial = publication.status {} else { Issue.record("Expected best-effort partial coverage: \(publication.status)") }
        let buffer = try SourceBuffer(path: "src/reader.cpp", data: Data(contentsOf: root.appending(path: "src/reader.cpp")))
        let semantics = DocumentSemantics.make(document: try #require(publication.index.documents[buffer.path]), buffer: buffer)
        let call = (buffer.text as NSString).range(of: "increment(4)").location
        let target = try #require(publication.index.target(in: semantics, at: buffer.byteOffset(forUTF16: call + 1)))
        #expect(target.displayName == "increment")
        #expect(target.definitions.first?.path == "src/api.cpp")
        #expect(ContentDigest.workingTreeBlobIDs(root: root, paths: paths) == original)
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "compile_commands.json").path))
        let command = try #require(publication.outcomes.first?.commandLine)
        let generatedPath = try #require(command.components(separatedBy: "--compdb-path ").last?.components(separatedBy: " --index-output-path").first)
        #expect(!FileManager.default.fileExists(atPath: generatedPath))
        await service.close()
        let reloaded = SemanticIndexService(indexers: [ScipClangIndexer()], cache: cache)
        let reloadSink = PublicationSink()
        await reloaded.open(snapshot) { await reloadSink.receive($0) }
        try await IndexingTests.waitUntil { reloadSink.latest?.status.isIndexing == false }
        #expect(reloadSink.latest?.outcomes.first?.result == .cached(stale: false))
        #expect(reloadSink.latest?.outcomes.first?.capability == .bestEffort)
        if case .partial = reloadSink.latest?.status {} else { Issue.record("Best effort must stay Partial after reload") }
        await reloaded.close()
    }
}
