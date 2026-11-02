import Foundation

/// Reopen the attached checkout and PR identity, never an evictable cached
/// worktree or a byte position belonging to an older head commit.
struct ReaderSession: Codable, Equatable, Sendable {
    let repositoryPath: String
    let pullRequest: Int?

    var isValid: Bool {
        repositoryPath.hasPrefix("/") && (pullRequest.map { $0 > 0 } ?? true)
    }

    var repositoryURL: URL {
        URL(filePath: repositoryPath, directoryHint: .isDirectory).standardizedFileURL.resolvingSymlinksInPath()
    }
}
