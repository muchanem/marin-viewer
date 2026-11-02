import Foundation
import Testing
@testable import Radiology

@Suite(.serialized)
struct ReviewRepositoryTests {
    @Test func fetchesPinnedCommitsByShaAndNeverWritesTheAttachedRepository() async throws {
        let fixture = try GitFixture.make()
        defer { fixture.remove() }
        let before = try GitFixture.run(["status", "--porcelain", "--branch"], in: fixture.attached)
        let beforeHead = try GitFixture.run(["rev-parse", "HEAD"], in: fixture.attached)
        let store = try ReviewRepository(attachedRoot: fixture.attached, cacheDirectory: fixture.cacheDirectory, git: GitFixture.git)
        #expect(await !store.hasCommit(fixture.headSHA), "the attached clone predates the branch")
        try await store.fetch([fixture.headSHA, fixture.baseSHA], fallbackRefs: ["refs/heads/feature"])
        #expect(await store.hasCommit(fixture.headSHA))
        #expect(await store.hasCommit(fixture.baseSHA), "the base commit comes through the alternates")
        // The bare store points at the attached repository's objects read-only.
        let alternates = try String(contentsOf: fixture.cacheDirectory.appending(path: "review.git/objects/info/alternates"), encoding: .utf8)
        #expect(alternates.contains(fixture.attached.path + "/.git/objects"))
        #expect(try GitFixture.run(["status", "--porcelain", "--branch"], in: fixture.attached) == before)
        #expect(try GitFixture.run(["rev-parse", "HEAD"], in: fixture.attached) == beforeHead)
        #expect(try GitFixture.run(["for-each-ref"], in: fixture.attached).contains("feature") == false, "no refs were added to the attached repository")
        // A SHA nobody has is an error that names the commit.
        await #expect(throws: BrowserError.self) {
            try await store.fetch(["0123456789012345678901234567890123456789"], fallbackRefs: ["refs/heads/main"])
        }
    }

    @Test func diffsNameStatusCountsHunksAndMaterializesBeforeBytes() async throws {
        let fixture = try GitFixture.make()
        defer { fixture.remove() }
        let store = try ReviewRepository(attachedRoot: fixture.attached, cacheDirectory: fixture.cacheDirectory, git: GitFixture.git)
        try await store.fetch([fixture.headSHA, fixture.baseSHA])
        let changes = try await store.changes(base: fixture.baseSHA, head: fixture.headSHA)
        let byPath = Dictionary(uniqueKeysWithValues: changes.map { ($0.path, $0) })
        #expect(Set(byPath.keys) == ["src/lib.rs", "src/old.rs", "docs/README.md", "src/new.rs", "crlf.txt", "uni.rs", "data/bin.dat"])
        #expect(byPath["src/lib.rs"]?.status == .modified)
        #expect(byPath["src/old.rs"]?.status == .deleted)
        #expect(byPath["src/new.rs"]?.status == .added)
        #expect(byPath["data/bin.dat"]?.isBinary == true)
        let rename = try #require(byPath["docs/README.md"])
        guard case .renamed(let similarity) = rename.status else { Issue.record("expected a rename, got \(rename.status)"); return }
        #expect(similarity < 100 && similarity >= 50)
        #expect(rename.oldPath == "docs/readme.md")
        #expect(rename.additions == 1 && rename.deletions == 0)
        #expect(byPath["src/lib.rs"]?.additions == 6 && byPath["src/lib.rs"]?.deletions == 1)
        #expect(changes.allSatisfy { $0.path != "docs/other.md" }, "main's later commit is not part of the pull request")

        let lib = try await store.lineChanges(base: fixture.baseSHA, head: fixture.headSHA, change: byPath["src/lib.rs"]!)
        #expect(lib.changedLines(in: .after) == [6..<12], "git's minimal diff keeps the closing brace")
        #expect(lib.changedLines(in: .before) == [6..<7])
        let crlf = try await store.lineChanges(base: fixture.baseSHA, head: fixture.headSHA, change: byPath["crlf.txt"]!)
        #expect(crlf.changedLines(in: .after) == [2..<3, 4..<5], "CRLF files are line-addressed like any other")
        let uni = try await store.lineChanges(base: fixture.baseSHA, head: fixture.headSHA, change: byPath["uni.rs"]!)
        #expect(uni.changedLines(in: .after) == [2..<4])
        let renamed = try await store.lineChanges(base: fixture.baseSHA, head: fixture.headSHA, change: rename)
        #expect(renamed.changedLines(in: .after) == [6..<7], "a rename with edits diffs old against new path")
        let deleted = try await store.lineChanges(base: fixture.baseSHA, head: fixture.headSHA, change: byPath["src/old.rs"]!)
        #expect(deleted.changedLines(in: .before) == [1..<2] && deleted.changedLines(in: .after).isEmpty)
        let binary = try await store.lineChanges(base: fixture.baseSHA, head: fixture.headSHA, change: byPath["data/bin.dat"]!)
        #expect(binary.isBinary)

        // Before bytes come from the base blob, by object id, into the revision's files directory.
        let root = try await store.materialize(blob: byPath["src/old.rs"]!.beforeBlob, path: "src/old.rs", revision: fixture.baseSHA)
        #expect(root == fixture.cacheDirectory.appending(path: "revisions/\(fixture.baseSHA)/files", directoryHint: .isDirectory))
        #expect(try String(contentsOf: root.appending(path: "src/old.rs"), encoding: .utf8) == "pub fn old() {}\n")
        let renamedRoot = try await store.materialize(blob: rename.beforeBlob, path: "docs/readme.md", revision: fixture.baseSHA)
        #expect(try String(contentsOf: renamedRoot.appending(path: "docs/readme.md"), encoding: .utf8).hasSuffix("Three\n"))
    }

    @Test func renamedBlobDiffExcludesAChildOfTheReusedOldPath() async throws {
        let fixture = try GitFixture.make()
        defer { fixture.remove() }
        try GitFixture.run(["checkout", "-q", "-b", "rename-child", fixture.baseSHA], in: fixture.origin)
        try GitFixture.run(["mv", "uni.rs", "new.rs"], in: fixture.origin)
        try GitFixture.write("unrelated\n", to: fixture.origin.appending(path: "uni.rs/added.rs"))
        try GitFixture.run(["add", "-A"], in: fixture.origin)
        try GitFixture.run(["commit", "-q", "-m", "reuse old rename path as directory"], in: fixture.origin)
        let head = try GitFixture.run(["rev-parse", "HEAD"], in: fixture.origin)
        let store = try ReviewRepository(attachedRoot: fixture.attached, cacheDirectory: fixture.cacheDirectory, git: GitFixture.git)
        try await store.fetch([fixture.baseSHA, head])
        let changes = try await store.changes(base: fixture.baseSHA, head: head)
        let rename = try #require(changes.first { $0.path == "new.rs" })
        #expect(rename.status == .renamed(similarity: 100) && rename.oldPath == "uni.rs")
        #expect(rename.beforeBlob.count == 40 && rename.afterBlob.count == 40)
        let diff = try await store.lineChanges(base: fixture.baseSHA, head: head, change: rename)
        #expect(diff.hunks.isEmpty, "the unrelated child must not highlight an unchanged renamed file")
        #expect(LineMap(diff).map(line: 3, from: .before) == 3)
        let added = try #require(changes.first { $0.path == "uni.rs/added.rs" })
        let addition = try await store.lineChanges(base: fixture.baseSHA, head: head, change: added)
        #expect(addition.changedLines(in: .after) == [1..<2])
        #expect(addition.changedLines(in: .before).isEmpty)
    }

    @Test func worktreesAreExactSnapshotsWithBlobIdsAndAreEvicted() async throws {
        let fixture = try GitFixture.make()
        defer { fixture.remove() }
        let store = try ReviewRepository(attachedRoot: fixture.attached, cacheDirectory: fixture.cacheDirectory, git: GitFixture.git)
        try await store.fetch([fixture.headSHA, fixture.baseSHA, fixture.mainSHA])
        let head = try await store.worktree(for: fixture.headSHA)
        #expect(try GitFixture.run(["rev-parse", "HEAD"], in: head) == fixture.headSHA)
        #expect(FileManager.default.fileExists(atPath: head.appending(path: "src/new.rs").path))
        #expect(!FileManager.default.fileExists(atPath: head.appending(path: "src/old.rs").path))
        let tree = try await store.tree(of: fixture.headSHA)
        let ids = Dictionary(uniqueKeysWithValues: tree.map { ($0.path, $0.blob) })
        #expect(ids["src/lib.rs"] == ContentDigest.blobID(of: try Data(contentsOf: head.appending(path: "src/lib.rs"))), "ls-tree ids equal hashed working bytes")
        #expect(ids["src/old.rs"] == nil)
        // Reopening reuses the existing worktree; a tampered one is replaced.
        #expect(try await store.worktree(for: fixture.headSHA) == head)
        try Data("tampered".utf8).write(to: head.appending(path: ".git"))
        let again = try await store.worktree(for: fixture.headSHA)
        #expect(try GitFixture.run(["rev-parse", "HEAD"], in: again) == fixture.headSHA)
        // The browsing snapshot is a Git repository the RepositoryWorker lists like any other.
        let snapshot = try await RepositoryWorker().open(again)
        #expect(snapshot.isGit)
        #expect(snapshot.files.map(\.path).contains("src/new.rs"))
        // Eviction keeps the most recent `worktreeLimit` trees.
        _ = try await store.worktree(for: fixture.baseSHA)
        _ = try await store.worktree(for: fixture.mainSHA)
        let revisions = fixture.cacheDirectory.appending(path: "revisions")
        let trees = try FileManager.default.contentsOfDirectory(atPath: revisions.path).filter {
            FileManager.default.fileExists(atPath: revisions.appending(path: "\($0)/tree/.git").path)
        }
        #expect(trees.count == ReviewRepository.worktreeLimit)
    }
}
