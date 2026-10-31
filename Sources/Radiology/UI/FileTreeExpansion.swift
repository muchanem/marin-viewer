import SwiftUI
import Observation

/// Expanded directories of the Files tree, by relative path. Explicit state
/// (rather than OutlineGroup's private state) survives filtering, refreshes,
/// and pull request snapshots whose trees have the same paths.
@Observable @MainActor
final class FileTreeExpansion {
    var expandedPaths: Set<String> = []

    func isExpanded(_ path: String) -> Bool { expandedPaths.contains(path) }

    func setExpanded(_ expanded: Bool, path: String) {
        if expanded { expandedPaths.insert(path) } else { expandedPaths.remove(path) }
    }

    func reveal(_ path: String) {
        let parts = path.split(separator: "/")
        guard parts.count > 1 else { return }
        expandedPaths.formUnion((1..<parts.count).map { parts.prefix($0).joined(separator: "/") })
    }

    func binding(for path: String) -> Binding<Bool> {
        Binding { [unowned self] in isExpanded(path) } set: { [unowned self] in setExpanded($0, path: path) }
    }

    func reset() {
        if !expandedPaths.isEmpty { expandedPaths = [] }
    }
}
