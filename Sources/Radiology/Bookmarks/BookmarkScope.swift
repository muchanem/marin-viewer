import Foundation

/// The attached checkout is stable across evictable PR worktrees and refreshes.
struct BookmarkScope: Hashable, Sendable {
    let repositoryPath: String
    let pullRequest: Int?

    init(root: URL, pullRequest: Int?) {
        repositoryPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        self.pullRequest = pullRequest
    }

    var key: String { repositoryPath + "\u{0}" + (pullRequest.map { "pr:\($0)" } ?? "checkout") }
}
