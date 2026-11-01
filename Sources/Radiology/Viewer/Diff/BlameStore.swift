import Foundation
import ViewerCore

/// `git blame --porcelain` per file and commit, parsed with ViewerCore and
/// kept for the life of the store. A commit's blame never changes, so the
/// key is the pair alone. Concurrent requests for one key share one run.
actor BlameStore {
    private struct Key: Hashable {
        let commit: String
        let path: String
    }

    private let commands = CommandRunner()
    private let git: URL
    private var cache: [Key: Blame] = [:]
    private var running: [Key: Task<Blame, Error>] = [:]
    /// Blame runs started, for tests of the cache.
    private(set) var runs = 0

    init(git: URL? = nil) {
        self.git = git ?? ToolLocator.executable("git") ?? URL(filePath: "/usr/bin/git")
    }

    func blame(path: String, commit: String, repository: URL) async throws -> Blame {
        let key = Key(commit: commit, path: path)
        if let cached = cache[key] { return cached }
        if let task = running[key] { return try await task.value }
        runs += 1
        let commands = commands, git = git
        let task = Task {
            let data = try await commands.run(git, arguments: ["blame", "--porcelain", commit, "--", path], directory: repository)
            return try BlameParser.parse(String(decoding: data, as: UTF8.self))
        }
        running[key] = task
        defer { running[key] = nil }
        let blame = try await task.value
        cache[key] = blame
        return blame
    }
}
