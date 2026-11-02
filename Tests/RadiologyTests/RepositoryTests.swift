import Foundation
import Testing
@testable import Radiology

struct RepositoryTests {
    @Test func folderDiscoverySkipsGeneratedDirectoriesAndBuildsTree() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: ".build"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("let value = 1".utf8).write(to: root.appending(path: "Sources/A.swift"))
        try Data().write(to: root.appending(path: ".build/ignored.swift"))
        try Data().write(to: root.appending(path: "README.md"))
        let snapshot = try await RepositoryWorker().open(root)
        #expect(!snapshot.isGit)
        #expect(snapshot.files.map(\.path) == ["README.md", "Sources/A.swift"])
        #expect(snapshot.tree.first?.name == "Sources")
        #expect(snapshot.tree.first?.children?.first?.path == "Sources/A.swift")
    }

    @Test func gitDiscoveryIncludesUntrackedFilesRespectsIgnoresAndFindsRoot() async throws {
        let git = try #require(ToolLocator.executable("git"))
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appending(path: "Sources"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = CommandRunner()
        _ = try await runner.run(git, arguments: ["init", "--quiet"], directory: root)
        try Data("ignored.swift\n".utf8).write(to: root.appending(path: ".gitignore"))
        try Data().write(to: root.appending(path: "ignored.swift"))
        try Data().write(to: root.appending(path: "Sources/space name.swift"))
        try Data().write(to: root.appending(path: "Sources/line\nbreak.swift"))
        let snapshot = try await RepositoryWorker().open(root.appending(path: "Sources"))
        #expect(snapshot.isGit)
        #expect(snapshot.root.resolvingSymlinksInPath() == root.resolvingSymlinksInPath())
        #expect(snapshot.files.count == 3)
        #expect(!snapshot.files.contains { $0.path == "ignored.swift" })
        #expect(snapshot.files.contains { $0.path == "Sources/line\nbreak.swift" })
    }

    @Test func sourceStoreRejectsSymlinksOutsideRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appending(path: "escape"), withDestinationURL: outside)
        await #expect(throws: BrowserError.self) { try await SourceStore().load(root: root, path: "escape") }
    }
}
