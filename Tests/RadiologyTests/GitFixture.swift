import Foundation
@testable import Radiology

/// A throwaway origin repository with a base commit, a later main commit,
/// and a feature branch, plus an "attached" clone taken before the branch
/// existed, so fetching the pull request really transfers objects. All git
/// invocations are synchronous `/usr/bin/git` runs; nothing touches any
/// repository outside the temporary directory.
struct GitFixture {
    let directory: URL
    let origin: URL
    let attached: URL
    let baseSHA: String
    let mainSHA: String
    let headSHA: String

    static let git = URL(filePath: "/usr/bin/git")

    @discardableResult
    static func run(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = git
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSTemporaryDirectory(), "GIT_AUTHOR_NAME": "Fixture", "GIT_AUTHOR_EMAIL": "f@x", "GIT_COMMITTER_NAME": "Fixture", "GIT_COMMITTER_EMAIL": "f@x", "GIT_CONFIG_NOSYSTEM": "1", "LC_ALL": "C"]
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BrowserError.message("git \(arguments.joined(separator: " ")) failed: \(String(decoding: errorData, as: UTF8.self))")
        }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    static func make() throws -> GitFixture {
        // The real path (no /var → /private/var symlink), so roots that git
        // reports compare equal to roots derived from this directory.
        let temporary = FileManager.default.temporaryDirectory.appending(path: "radiology-git-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let directory = URL(filePath: String(cString: realpath(temporary.path, nil)), directoryHint: .isDirectory)
        let origin = directory.appending(path: "origin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try run(["init", "-q", "-b", "main"], in: origin)
        try run(["config", "uploadpack.allowAnySHA1InWant", "true"], in: origin)
        try run(["config", "uploadpack.allowReachableSHA1InWant", "true"], in: origin)
        // Base commit.
        try write("[package]\nname = \"fixture\"\nversion = \"0.1.0\"\n", to: origin.appending(path: "Cargo.toml"))
        try write("pub fn a() -> i32 {\n    1\n}\n\npub fn b() -> i32 {\n    2\n}\n", to: origin.appending(path: "src/lib.rs"))
        try write("pub fn old() {}\n", to: origin.appending(path: "src/old.rs"))
        try write("# Readme\n\nOne\nTwo\nThree\n", to: origin.appending(path: "docs/readme.md"))
        try write("Other\n", to: origin.appending(path: "docs/other.md"))
        try write("line1\r\nline2\r\nline3\r\n", to: origin.appending(path: "crlf.txt"))
        try write("fn café() {\n    let 🚀 = 1;\n}\n", to: origin.appending(path: "uni.rs"))
        try write("x = 1\n", to: origin.appending(path: "tools/setup.py"))
        try FileManager.default.createDirectory(at: origin.appending(path: "data"), withIntermediateDirectories: true)
        try Data([0x00, 0x01, 0x02, 0xFF]).write(to: origin.appending(path: "data/bin.dat"))
        try run(["add", "-A"], in: origin)
        try run(["commit", "-q", "-m", "base"], in: origin)
        let baseSHA = try run(["rev-parse", "HEAD"], in: origin)
        // The attached clone is taken now, before the branch exists.
        let attached = directory.appending(path: "attached", directoryHint: .isDirectory)
        try run(["clone", "-q", "file://" + origin.path, attached.path], in: directory)
        // Feature branch from base.
        try run(["checkout", "-q", "-b", "feature"], in: origin)
        try write("pub fn a() -> i32 {\n    1\n}\n\npub fn b() -> i32 {\n    let extra = 40;\n    extra + 2\n}\n\npub fn c() -> i32 {\n    3\n}\n", to: origin.appending(path: "src/lib.rs"))
        try FileManager.default.removeItem(at: origin.appending(path: "src/old.rs"))
        try run(["mv", "docs/readme.md", "docs/README.md"], in: origin)
        try write("# Readme\n\nOne\nTwo\nThree\nFour\n", to: origin.appending(path: "docs/README.md"))
        try write("pub fn fresh() {}\n", to: origin.appending(path: "src/new.rs"))
        try write("line1\r\nline2 changed\r\nline3\r\nline4\r\n", to: origin.appending(path: "crlf.txt"))
        try write("fn café() {\n    let 🚀 = 2;\n    let ñ = 3;\n}\n", to: origin.appending(path: "uni.rs"))
        try Data([0x00, 0x01, 0x03, 0xFF, 0xFE]).write(to: origin.appending(path: "data/bin.dat"))
        try run(["add", "-A"], in: origin)
        try run(["commit", "-q", "-m", "feature"], in: origin)
        let headSHA = try run(["rev-parse", "HEAD"], in: origin)
        // main moves on, so the merge base is not main's tip.
        try run(["checkout", "-q", "main"], in: origin)
        try write("Other changed\n", to: origin.appending(path: "docs/other.md"))
        try run(["commit", "-q", "-am", "main moves"], in: origin)
        let mainSHA = try run(["rev-parse", "HEAD"], in: origin)
        return GitFixture(directory: directory, origin: origin, attached: attached, baseSHA: baseSHA, mainSHA: mainSHA, headSHA: headSHA)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    var cacheDirectory: URL { directory.appending(path: "cache", directoryHint: .isDirectory) }

    func summary(number: Int = 1) -> PullRequestSummary {
        PullRequestSummary(number: number, title: "Feature work", state: "OPEN", baseRefName: "main", baseRefOid: mainSHA,
                           headRefName: "feature", headRefOid: headSHA, isCrossRepository: false, updatedAt: .now, mergeCommit: nil,
                           author: PullRequestSummary.Author(login: "fixture"))
    }
}

/// A GitHub client that answers from a fixture without any network.
final class FakeGitHubClient: GitHubClient, @unchecked Sendable {
    var summaries: [Int: PullRequestSummary]
    var mergeBases: [String: String]
    var repositoryError: String?
    var listDelay: Duration = .zero
    var pullRequestDelay: Duration = .zero
    var pullRequestError: String?
    var ignoresPullRequestCancellation = false
    private(set) var listCalls = 0
    private(set) var viewCalls = 0

    init(summaries: [Int: PullRequestSummary], mergeBase: String) {
        self.summaries = summaries
        mergeBases = Dictionary(uniqueKeysWithValues: summaries.values.map { ("\($0.baseRefOid)...\($0.headRefOid)", mergeBase) })
    }

    func repository(at root: URL) async throws -> GitHubRepository {
        if let repositoryError { throw BrowserError.message(repositoryError) }
        return GitHubRepository(nameWithOwner: "fixture/repo", url: "https://example.invalid/fixture/repo", defaultBranch: "main")
    }

    func listPullRequests(in repository: GitHubRepository, limit: Int) async throws -> [PullRequestSummary] {
        listCalls += 1
        if listDelay > .zero { try await Task.sleep(for: listDelay) }
        return summaries.values.sorted { $0.number > $1.number }.prefix(limit).map { $0 }
    }

    func pullRequest(number: Int, in repository: GitHubRepository) async throws -> PullRequestSummary {
        viewCalls += 1
        if pullRequestDelay > .zero {
            if ignoresPullRequestCancellation { try? await Task.sleep(for: pullRequestDelay) }
            else { try await Task.sleep(for: pullRequestDelay) }
        }
        if let pullRequestError { throw BrowserError.message(pullRequestError) }
        guard let summary = summaries[number] else { throw BrowserError.message("no pull requests found for \(number)") }
        return summary
    }

    func mergeBase(base: String, head: String, in repository: GitHubRepository) async throws -> String {
        guard let sha = mergeBases["\(base)...\(head)"] else { throw BrowserError.message("no merge base") }
        return sha
    }
}
