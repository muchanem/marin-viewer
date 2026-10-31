import Foundation

/// Keep the active document visible without changing the saved filters or
/// the repository snapshot. Before-only PR paths can be represented too.
struct FilesSidebarPresentation {
    let tree: [FileNode]
    let files: [RepositoryFile]
    let currentFile: RepositoryFile?
    let addsTreeException: Bool
    let addsFilterException: Bool
    let currentFileOutsideSnapshot: Bool

    init(repository: RepositorySnapshot, tree: [FileNode], files: [RepositoryFile], filters: SourceFilters,
         path: String?, loadedPath: String?, isBeforePath: Bool) {
        let listed = path.flatMap { path in repository.files.first { $0.path == path } }
        let current = listed ?? path.flatMap { path in
            loadedPath == path || isBeforePath ? RepositoryFile(path: path) : nil
        }
        currentFile = current
        currentFileOutsideSnapshot = current != nil && listed == nil
        addsTreeException = current.map { listed == nil || !filters.includes($0.path) } ?? false
        addsFilterException = current.map { current in !files.contains { $0.path == current.path } } ?? false
        if addsTreeException, let current {
            self.tree = FileNode.revealing(current, in: tree)
        } else { self.tree = tree }
        if addsFilterException, let current {
            self.files = (files + [current]).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        } else { self.files = files }
    }
}
