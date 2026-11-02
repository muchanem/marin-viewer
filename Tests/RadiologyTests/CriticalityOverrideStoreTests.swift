import Foundation
import Testing
@testable import Radiology

/// Decisions persist per repository outside the viewed tree and never leak
/// between repositories.
struct CriticalityOverrideStoreTests {
    @Test func roundTripIsolationAndTolerance() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-overrides-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repoA = FileManager.default.temporaryDirectory.appending(path: "repo-a-\(UUID().uuidString)", directoryHint: .isDirectory)
        let repoB = FileManager.default.temporaryDirectory.appending(path: "repo-b-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: repoA, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoA) }
        let store = CriticalityOverrideStore(directory: directory)
        #expect(await store.load(for: repoA).isEmpty)

        var overrides = CriticalityOverrides()
        overrides.setSymbol("rust-analyzer cargo std https://x fs/write().", to: .ordinary)
        overrides.setPackage("rust-analyzer cargo serde_json", to: .critical)
        try await store.save(overrides, for: repoA)
        let file = store.fileURL(for: repoA)
        #expect(file.path.hasPrefix(directory.path), "stored under the app's directory")
        #expect(!file.path.hasPrefix(repoA.path), "never inside the repository")
        #expect(try FileManager.default.contentsOfDirectory(atPath: repoA.path).isEmpty, "the repository is untouched")
        let loaded = await store.load(for: repoA)
        #expect(loaded.symbols == overrides.symbols)
        #expect(loaded.packages == overrides.packages)
        #expect(loaded.repositoryRoot == CriticalityOverrideStore.canonicalPath(repoA))
        #expect(await store.load(for: repoB).isEmpty, "another repository sees nothing")

        // Corrupt and mismatched files are treated as empty, not trusted.
        try Data("{not json".utf8).write(to: file)
        #expect(await store.load(for: repoA).isEmpty)
        var foreign = overrides
        foreign.repositoryRoot = "/somewhere/else"
        try JSONEncoder().encode(foreign).write(to: file)
        #expect(await store.load(for: repoA).isEmpty, "a file for a different root is ignored")

        // Removing every decision removes the file.
        try await store.save(CriticalityOverrides(), for: repoA)
        #expect(!FileManager.default.fileExists(atPath: file.path))

        // An older revision arriving after a newer one is skipped.
        var newer = CriticalityOverrides()
        newer.setPackage("rust-analyzer cargo tokio", to: .critical)
        try await store.save(newer, for: repoA, revision: 10)
        try await store.save(overrides, for: repoA, revision: 9)
        #expect(await store.load(for: repoA).packages == newer.packages)
        try await store.save(CriticalityOverrides(), for: repoA, revision: 11)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func deletionFailuresAreReported() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "radiology-overrides-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = FileManager.default.temporaryDirectory.appending(path: "repo-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = CriticalityOverrideStore(directory: directory)
        var overrides = CriticalityOverrides()
        overrides.setPackage("rust-analyzer cargo std", to: .critical)
        try await store.save(overrides, for: repo, revision: 1)
        // A read-only parent directory makes the deletion fail: the error surfaces instead of being swallowed.
        let file = store.fileURL(for: repo)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        await #expect(throws: (any Error).self) { try await store.save(CriticalityOverrides(), for: repo, revision: 2) }
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
