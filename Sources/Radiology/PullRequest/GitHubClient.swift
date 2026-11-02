import Foundation

/// The GitHub repository an attached folder pushes to, as `gh` resolves it.
struct GitHubRepository: Hashable, Sendable {
    /// `owner/name`
    let nameWithOwner: String
    let url: String
    let defaultBranch: String
}

/// One pull request as `gh pr list` / `gh pr view` report it. The SHAs are
/// the ones GitHub holds at the moment of the query: `headRefOid` is the
/// commit a review pins, and `baseRefOid` is GitHub's base commit, from which
/// the merge base is computed. A later push produces a different summary.
struct PullRequestSummary: Identifiable, Hashable, Sendable, Codable {
    struct MergeCommit: Hashable, Sendable, Codable { let oid: String }
    struct Author: Hashable, Sendable, Codable { let login: String }

    let number: Int
    let title: String
    /// `OPEN`, `MERGED`, or `CLOSED`.
    let state: String
    let baseRefName: String
    let baseRefOid: String
    let headRefName: String
    let headRefOid: String
    let isCrossRepository: Bool
    let updatedAt: Date
    let mergeCommit: MergeCommit?
    let author: Author?

    var id: Int { number }
    var stateTitle: String {
        switch state {
        case "OPEN": "Open"
        case "MERGED": "Merged"
        case "CLOSED": "Closed"
        default: state.capitalized
        }
    }
    var isMerged: Bool { state == "MERGED" }

    static let jsonFields = "number,title,state,baseRefName,baseRefOid,headRefName,headRefOid,isCrossRepository,updatedAt,mergeCommit,author"
}

/// Read-only GitHub access. Nothing here can write to GitHub.
protocol GitHubClient: Sendable {
    func repository(at root: URL) async throws -> GitHubRepository
    func listPullRequests(in repository: GitHubRepository, limit: Int) async throws -> [PullRequestSummary]
    func pullRequest(number: Int, in repository: GitHubRepository) async throws -> PullRequestSummary
    /// The merge base GitHub's own three-dot diff uses for `base...head`.
    func mergeBase(base: String, head: String, in repository: GitHubRepository) async throws -> String
}

/// `gh`-backed client. Every call runs the CLI with a timeout and surfaces
/// its stderr verbatim when it fails (not logged in, no such PR, no network).
struct GHCommandClient: GitHubClient {
    let timeout: Duration
    private let commands = CommandRunner()

    init(timeout: Duration = .seconds(30)) {
        self.timeout = timeout
    }

    static func executable() -> URL? {
        ToolLocator.executable("gh")
    }

    func repository(at root: URL) async throws -> GitHubRepository {
        struct View: Decodable {
            struct Branch: Decodable { let name: String }
            let nameWithOwner: String
            let url: String
            let defaultBranchRef: Branch?
        }
        let data = try await run(["repo", "view", "--json", "nameWithOwner,url,defaultBranchRef"], directory: root)
        let view = try decode(View.self, from: data)
        return GitHubRepository(nameWithOwner: view.nameWithOwner, url: view.url, defaultBranch: view.defaultBranchRef?.name ?? "main")
    }

    func listPullRequests(in repository: GitHubRepository, limit: Int) async throws -> [PullRequestSummary] {
        let data = try await run(["pr", "list", "-R", repository.nameWithOwner, "--state", "all", "--limit", "\(max(1, limit))",
                                  "--json", PullRequestSummary.jsonFields], directory: nil)
        return try decode([PullRequestSummary].self, from: data)
    }

    func pullRequest(number: Int, in repository: GitHubRepository) async throws -> PullRequestSummary {
        let data = try await run(["pr", "view", "\(number)", "-R", repository.nameWithOwner, "--json", PullRequestSummary.jsonFields], directory: nil)
        return try decode(PullRequestSummary.self, from: data)
    }

    func mergeBase(base: String, head: String, in repository: GitHubRepository) async throws -> String {
        struct Compare: Decodable {
            struct Commit: Decodable { let sha: String }
            let merge_base_commit: Commit
        }
        let data = try await run(["api", "repos/\(repository.nameWithOwner)/compare/\(base)...\(head)"], directory: nil)
        let compare = try decode(Compare.self, from: data)
        guard Self.isSHA(compare.merge_base_commit.sha) else { throw BrowserError.message("GitHub returned no merge base for \(base.prefix(10))...\(head.prefix(10)).") }
        return compare.merge_base_commit.sha
    }

    static func isSHA(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy { $0.isHexDigit }
    }

    private func run(_ arguments: [String], directory: URL?) async throws -> Data {
        guard let gh = Self.executable() else {
            throw BrowserError.message("The GitHub CLI (gh) was not found. Install it and run `gh auth login`.")
        }
        do {
            return try await TimedCommand.run(commands, gh, arguments: arguments, directory: directory ?? URL(filePath: NSHomeDirectory()),
                                              timeout: timeout, environment: ToolDirectory.childEnvironment(extra: ["GH_PROMPT_DISABLED": "1", "NO_COLOR": "1"]))
        } catch let error as BrowserError {
            throw BrowserError.message("gh \(arguments.prefix(2).joined(separator: " ")) failed: \(error.localizedDescription)")
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw BrowserError.message("gh returned unexpected JSON: \(error.localizedDescription)")
        }
    }
}

/// Runs a command with a wall-clock limit. The command is cancelled (and its
/// process terminated through `CommandRunner`'s cancellation handler) when
/// the limit passes or the caller's task is cancelled.
enum TimedCommand {
    static func run(_ commands: CommandRunner, _ executable: URL, arguments: [String], directory: URL,
                    timeout: Duration, environment: [String: String]? = nil) async throws -> Data {
        try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                try await commands.run(executable, arguments: arguments, directory: directory, environment: environment)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw BrowserError.message("\(executable.lastPathComponent) \(arguments.first ?? "") did not finish within \(Int(timeout.components.seconds)) seconds.")
            }
            guard let result = try await group.next() else { throw CancellationError() }
            group.cancelAll()
            return result
        }
    }
}
