import Foundation

extension AppModel {
    var canBookmarkCurrentLocation: Bool {
        bookmarks.scope != nil && currentCaretLocation != nil && !isLoadingSource && !isOpening && !pullRequests.isLoading
    }

    var isCurrentLocationBookmarked: Bool {
        _ = sourceCaretRevision
        return currentCaretLocation.flatMap { bookmarks.bookmark(in: $0) } != nil
    }

    func toggleCurrentBookmark() {
        guard canBookmarkCurrentLocation, let source, let caret = currentCaretLocation else { return }
        let label = context.declaration?.declaration.name ?? URL(filePath: source.path).lastPathComponent
        bookmarks.toggle(SourceBookmark.make(in: source, at: caret.byteOffset, label: label))
    }

    func goToBookmark(slot: Int) {
        guard (0..<10).contains(slot), let bookmark = bookmarks.bookmark(at: slot) else { return }
        goToBookmark(id: bookmark.id)
    }

    func goToBookmark(id: UUID) {
        guard !isOpening, !pullRequests.isLoading, let repository, let scope = bookmarks.scope,
              let bookmark = bookmarks.entries.first(where: { $0.id == id }) else { return }
        bookmarkNavigationTask?.cancel()
        bookmarks.navigationError = nil
        let navigation = navigationRevision
        let caret = sourceCaretRevision
        let origin = currentCaretLocation
        let openBuffer = source
        bookmarkNavigationTask = Task { [bookmarkResolver] in
            do {
                let root = try await sourceRoot(for: bookmark.location)
                let resolved = try await bookmarkResolver.resolve(bookmark, root: root, openBuffer: openBuffer)
                let destination = resolved.location
                guard !Task.isCancelled, scope == bookmarks.scope, repository.root == self.repository?.root,
                      navigation == navigationRevision, caret == sourceCaretRevision,
                      bookmarks.entries.contains(where: { $0.id == id }) else { return }
                if let revision = destination.revision, let change = review?.change(touching: destination.path) {
                    pullRequests.revisionChoices[change.id] = revision
                }
                navigateFromCaret(from: origin ?? destination, to: destination)
                bookmarks.update(resolved)
                bookmarks.selectedID = id
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, scope == bookmarks.scope, repository.root == self.repository?.root,
                      navigation == navigationRevision, caret == sourceCaretRevision else { return }
                bookmarks.navigationError = error.localizedDescription
            }
        }
    }
}
