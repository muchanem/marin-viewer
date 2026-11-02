import Foundation

/// Hide Tests and Source Files Only: the filtered Files tree and the inline
/// test-code projection. See plans/source-filters.md.
extension AppModel {
    var filesSidebarPresentation: FilesSidebarPresentation? {
        guard let repository else { return nil }
        let path = selectedPath ?? source?.path
        let before = path.flatMap { review?.change(path: $0, in: .before) }?.existsBefore == true
            && (source?.revision == .before || navigationTarget?.revision == .before)
        return FilesSidebarPresentation(repository: repository, tree: fileTree, files: filteredFiles,
                                        filters: sourceFilters, path: path, loadedPath: source?.path, isBeforePath: before)
    }

    /// Rebuilds the Files tree and the filter-field list from the browsed
    /// repository. The repository model itself is never filtered.
    func refreshFileTree() {
        guard let repository else {
            fileTree = []
            visibleFileCount = 0
            filteredFiles = []
            return
        }
        if sourceFilters.isActive {
            let filters = sourceFilters
            let visible = repository.files.filter { filters.includes($0.path) }
            fileTree = FileNode.tree(files: visible)
            visibleFileCount = visible.count
        } else {
            fileTree = repository.tree
            visibleFileCount = repository.files.count
        }
        filterFiles()
    }

    /// The open file is filtered out of the tree (it stays open and readable).
    var isOpenFileFilteredOut: Bool {
        guard let path = source?.path ?? selectedPath else { return false }
        return !sourceFilters.includes(path)
    }

    /// The open document is test code as a whole: shown in full when opened.
    var isTestDocument: Bool {
        guard let source else { return false }
        if TestPathClassifier.isTestPath(source.path) { return true }
        return syntax?.path == source.path && syntax?.isTestOnlyDocument == true
    }

    /// Hide Tests' projection for exactly the loaded bytes, or nil.
    var testCodePresentation: TestCodePresentation? {
        guard sourceFilters.hidesTests, let source, let syntax, syntax.path == source.path,
              !syntax.testRegions.isEmpty, let sourceContentIdentity, !isTestDocument else { return nil }
        return TestCodePresentation(regions: syntax.testRegions, revealed: revealedTestRegions,
                                    buffer: source, sourceIdentity: sourceContentIdentity)
    }

    /// Outline declarations, without those inside hidden test regions.
    var outlineSymbols: [DocumentSymbol] {
        guard let syntax else { return [] }
        guard let presentation = testCodePresentation, !presentation.hiddenRegions.isEmpty else { return syntax.symbols }
        return syntax.symbols.filter { !presentation.hides($0.byteRange) }
    }

    func clearSourceFilters() { sourceFilters = SourceFilters() }

    func toggleTestRegion(_ id: Int) {
        if revealedTestRegions.contains(id) {
            revealedTestRegions.remove(id)
        } else {
            revealedTestRegions.insert(id)
        }
    }

    /// Explicit navigation into a hidden region reveals it before the
    /// viewer scrolls there.
    func revealTestCode(at byte: Int) {
        guard sourceFilters.hidesTests, let source, let syntax, syntax.path == source.path,
              let region = syntax.testRegions.first(where: { $0.byteRange.contains(byte) }),
              !revealedTestRegions.contains(region.id) else { return }
        revealedTestRegions.insert(region.id)
    }
}
