import Foundation

extension AppModel {
    func showAllInspectorPanes() { inspectorPanes = .all }

    func showBookmarksPane() {
        inspectorPanes.bookmarks = true
        inspectorRevealRevision += 1
    }
}
