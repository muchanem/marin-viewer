import Foundation

struct RepositorySnapshot: Sendable {
    let root: URL
    let files: [RepositoryFile]
    let tree: [FileNode]
    let isGit: Bool
}
