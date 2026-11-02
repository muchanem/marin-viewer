import Foundation

/// One entry of `git ls-tree -r`: a path and the blob it holds.
struct TreeEntry: Hashable, Sendable {
    let path: String
    let blob: String
    let mode: String
}

/// The app-owned Git store behind pull request reviews. It lives in the
/// repository's cache directory, never inside the attached folder:
///
/// - `review.git` is a bare repository whose `objects/info/alternates` points
///   at the attached repository's object store (read only) and whose `origin`
///   is the attached repository's `origin` URL. Commits are fetched by SHA at
///   depth 1, so a review needs only the merge base and the head.
/// - `revisions/<sha>/tree` is a detached worktree of the head: a complete
///   snapshot for browsing and indexing.
/// - `revisions/<sha>/files/<path>` holds base blobs materialized on demand
///   for the Before view of changed files.
///
/// The only commands run inside the attached folder are `rev-parse --git-path
/// objects` and `remote get-url origin`. Every command has a timeout and
/// honors task cancellation.
actor ReviewRepository {
    let attachedRoot: URL
    let cacheDirectory: URL
    private let commands = CommandRunner()
    private let git: URL
    private var prepared = false
    private var alternates: URL?
    private var worktreeLeases: [UUID: String] = [:]
    private let retainedWorktreeLimit: Int

    static let fetchTimeout: Duration = .seconds(300)
    static let worktreeTimeout: Duration = .seconds(180)
    static let commandTimeout: Duration = .seconds(60)
    /// Worktrees kept on disk; the least recently used beyond this are removed.
    static let worktreeLimit = 3

    init(attachedRoot: URL, cacheDirectory: URL, git: URL? = nil, worktreeLimit: Int = ReviewRepository.worktreeLimit) throws {
        guard let git = git ?? ToolLocator.executable("git") else {
            throw BrowserError.message("Git was not found. Pull request review needs the git command-line tool.")
        }
        self.attachedRoot = attachedRoot
        self.cacheDirectory = cacheDirectory
        self.git = git
        retainedWorktreeLimit = max(1, worktreeLimit)
    }

    var objectsDirectory: URL { cacheDirectory.appending(path: "review.git", directoryHint: .isDirectory) }
    func revisionDirectory(_ sha: String) -> URL { cacheDirectory.appending(path: "revisions/\(sha)", directoryHint: .isDirectory) }
    func worktreeDirectory(_ sha: String) -> URL { revisionDirectory(sha).appending(path: "tree", directoryHint: .isDirectory) }
    func filesDirectory(_ sha: String) -> URL { revisionDirectory(sha).appending(path: "files", directoryHint: .isDirectory) }
    func indexDirectory(_ sha: String) -> URL { revisionDirectory(sha).appending(path: "index", directoryHint: .isDirectory) }

    func protectHead(_ sha: String, lease: UUID) { worktreeLeases[lease] = sha }
    func releaseHead(lease: UUID) async {
        worktreeLeases.removeValue(forKey: lease)
        if let active = worktreeLeases.values.first { await evictWorktrees(keeping: active) }
    }

    // MARK: - Setup

    /// Creates the bare repository on first use and points it at the attached
    /// repository's objects and origin. Idempotent.
    func prepare() async throws {
        guard !prepared else { return }
        let objects = try await attachedGit(["rev-parse", "--path-format=absolute", "--git-path", "objects"])
        let origin = try await attachedGit(["remote", "get-url", "origin"])
        guard !origin.isEmpty else { throw BrowserError.message("The repository has no `origin` remote to fetch pull requests from.") }
        let directory = objectsDirectory
        if !FileManager.default.fileExists(atPath: directory.appending(path: "HEAD").path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            _ = try await run(["init", "--bare", "--quiet"], in: directory)
        }
        let alternatesURL = directory.appending(path: "objects/info/alternates")
        try FileManager.default.createDirectory(at: alternatesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((objects + "\n").utf8).write(to: alternatesURL, options: .atomic)
        alternates = URL(filePath: objects)
        let existing = (try? await run(["remote", "get-url", "origin"], in: directory)).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        if existing == nil {
            _ = try await run(["remote", "add", "origin", origin], in: directory)
        } else if existing != origin {
            _ = try await run(["remote", "set-url", "origin", origin], in: directory)
        }
        prepared = true
    }

    // MARK: - Objects

    func hasCommit(_ sha: String) async -> Bool {
        (try? await run(["cat-file", "-e", "\(sha)^{commit}"], in: objectsDirectory)) != nil
    }

    /// Fetches the given commits by SHA at depth 1. Commits already present
    /// (through the alternates or an earlier fetch) are skipped. When the
    /// server refuses a SHA, `fallbackRefs` (for example `refs/pull/N/head`)
    /// are fetched instead and the SHAs are checked again.
    func fetch(_ shas: [String], fallbackRefs: [String] = []) async throws {
        try await prepare()
        var missing: [String] = []
        for sha in shas where !(await hasCommit(sha)) { missing.append(sha) }
        guard !missing.isEmpty else { return }
        do {
            _ = try await run(["fetch", "--no-tags", "--depth=1", "--quiet", "origin"] + missing, in: objectsDirectory, timeout: Self.fetchTimeout)
        } catch let error as BrowserError {
            guard !fallbackRefs.isEmpty else { throw error }
            // A ref fetch brings whatever the ref points at *now*. Only the
            // pinned SHAs matter: the check below rejects a branch that
            // moved between the metadata query and the fetch.
            _ = try await run(["fetch", "--no-tags", "--depth=1", "--quiet", "origin"] + fallbackRefs, in: objectsDirectory, timeout: Self.fetchTimeout)
        }
        for sha in missing where !(await hasCommit(sha)) {
            throw BrowserError.message("Commit \(sha.prefix(10)) is not available from origin. The branch may have moved or been rewritten since the pull request was listed; reload the list and try again.")
        }
    }

    /// Every file in a commit with its blob id.
    func tree(of sha: String) async throws -> [TreeEntry] {
        let data = try await run(["ls-tree", "-r", "-z", sha], in: objectsDirectory)
        return data.split(separator: 0).compactMap { record -> TreeEntry? in
            let text = String(decoding: record, as: UTF8.self)
            guard let tab = text.firstIndex(of: "\t") else { return nil }
            let fields = text[..<tab].split(separator: " ")
            guard fields.count == 3 else { return nil }
            return TreeEntry(path: String(text[text.index(after: tab)...]), blob: String(fields[2]), mode: String(fields[0]))
        }
    }

    // MARK: - Diffs

    /// The files a pull request changes between its merge base and head.
    func changes(base: String, head: String) async throws -> [FileChange] {
        let raw = try await run(["diff", "--raw", "--abbrev=40", "-M", "-z", "--no-color", "--no-ext-diff", "--no-textconv", base, head], in: objectsDirectory)
        let numstat = try await run(["diff", "--numstat", "-M", "-z", "--no-color", "--no-ext-diff", "--no-textconv", base, head], in: objectsDirectory)
        return FileChangeParser.applyNumstat(numstat, to: try FileChangeParser.parseRaw(raw))
    }

    /// Hunks of one changed path.
    func lineChanges(base: String, head: String, change: FileChange) async throws -> FileLineChanges {
        guard !change.isBinary else { return .binary }
        // Compare this change's exact blobs, not pathspecs: a renamed old path
        // can also be reused by an unrelated added file in the same commit.
        let empty = (!change.existsBefore || !change.existsAfter) ? try await emptyBlob() : ""
        let before = change.existsBefore ? change.beforeBlob : empty
        let after = change.existsAfter ? change.afterBlob : empty
        let data = try await run(["diff", "-U0", "--no-color", "--no-ext-diff", "--no-textconv", before, after], in: objectsDirectory)
        return try UnifiedDiffParser.parse(String(decoding: data, as: UTF8.self))
    }

    private func emptyBlob() async throws -> String {
        let file = cacheDirectory.appending(path: "empty-blob")
        try Data().write(to: file, options: .atomic)
        return String(decoding: try await run(["hash-object", "-w", file.path], in: objectsDirectory), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Snapshots

    /// Writes one Before blob under `revisions/<sha>/files/<path>` and returns
    /// that files directory as a source root. Existing files are reused.
    func materialize(blob: String, path: String, revision sha: String) async throws -> URL {
        let root = filesDirectory(sha)
        let destination = root.appending(path: path)
        if FileManager.default.fileExists(atPath: destination.path) { return root }
        let data = try await run(["cat-file", "blob", blob], in: objectsDirectory)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        return root
    }

    /// A detached worktree of the commit, created on first use. A worktree
    /// left behind by an earlier session is verified to point at the same
    /// commit before it is reused.
    func worktree(for sha: String) async throws -> URL {
        try await prepare()
        let directory = worktreeDirectory(sha)
        if FileManager.default.fileExists(atPath: directory.appending(path: ".git").path) {
            if let head = try? await run(["rev-parse", "HEAD"], in: directory), String(decoding: head, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == sha {
                touch(directory)
                return directory
            }
            _ = try? await run(["worktree", "remove", "--force", directory.path], in: objectsDirectory)
            try? FileManager.default.removeItem(at: directory)
        }
        _ = try? await run(["worktree", "prune"], in: objectsDirectory)
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try await run(["worktree", "add", "--detach", directory.path, sha], in: objectsDirectory, timeout: Self.worktreeTimeout)
        touch(directory)
        await evictWorktrees(keeping: sha)
        return directory
    }

    private func touch(_ directory: URL) {
        try? Data("\(Date.now.timeIntervalSince1970)".utf8).write(to: directory.deletingLastPathComponent().appending(path: "last-used"), options: .atomic)
    }

    /// Removes the least recently used worktrees beyond the limit. Index
    /// caches and materialized Before files stay; they are small.
    func evictWorktrees(keeping current: String) async {
        let revisions = cacheDirectory.appending(path: "revisions", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: revisions.path) else { return }
        var candidates: [(sha: String, used: Double)] = []
        for name in names where name != current {
            let tree = revisions.appending(path: "\(name)/tree")
            guard FileManager.default.fileExists(atPath: tree.appending(path: ".git").path) else { continue }
            let stamp = (try? String(contentsOf: revisions.appending(path: "\(name)/last-used"), encoding: .utf8)).flatMap(Double.init) ?? 0
            candidates.append((name, stamp))
        }
        candidates.sort { $0.used > $1.used }
        for victim in candidates.dropFirst(max(0, retainedWorktreeLimit - 1)) where !worktreeLeases.values.contains(victim.sha) {
            _ = try? await run(["worktree", "remove", "--force", revisions.appending(path: "\(victim.sha)/tree").path], in: objectsDirectory)
            try? FileManager.default.removeItem(at: revisions.appending(path: "\(victim.sha)/tree"))
        }
        _ = try? await run(["worktree", "prune"], in: objectsDirectory)
    }

    /// Revision directories that hold an index cache, newest use first, for
    /// cross-revision index reuse.
    func indexedRevisions() -> [String] {
        let revisions = cacheDirectory.appending(path: "revisions", directoryHint: .isDirectory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: revisions.path) else { return [] }
        return names.filter { FileManager.default.fileExists(atPath: revisions.appending(path: "\($0)/index/index-metadata.json").path) }
            .sorted { lhs, rhs in
                let l = (try? String(contentsOf: revisions.appending(path: "\(lhs)/last-used"), encoding: .utf8)).flatMap(Double.init) ?? 0
                let r = (try? String(contentsOf: revisions.appending(path: "\(rhs)/last-used"), encoding: .utf8)).flatMap(Double.init) ?? 0
                return l > r
            }
    }

    // MARK: - Commands

    private func attachedGit(_ arguments: [String]) async throws -> String {
        let data = try await run(arguments, in: attachedRoot)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(_ arguments: [String], in directory: URL, timeout: Duration = ReviewRepository.commandTimeout) async throws -> Data {
        var environment = ToolDirectory.childEnvironment(extra: ["GIT_TERMINAL_PROMPT": "0", "LC_ALL": "C"])
        environment["GIT_OPTIONAL_LOCKS"] = "0"
        return try await TimedCommand.run(commands, git, arguments: arguments, directory: directory, timeout: timeout, environment: environment)
    }
}
