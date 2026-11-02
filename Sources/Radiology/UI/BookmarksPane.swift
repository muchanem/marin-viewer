import SwiftUI

struct BookmarksPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var bookmarks = model.bookmarks
        VStack(spacing: 0) {
            ContextRegionHeader(title: "Bookmarks", detail: scopeTitle) {
                Button(model.isCurrentLocationBookmarked ? "Remove Bookmark" : "Bookmark Location",
                       systemImage: model.isCurrentLocationBookmarked ? "bookmark.fill" : "bookmark",
                       action: model.toggleCurrentBookmark)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!model.canBookmarkCurrentLocation)
                    .help(model.isCurrentLocationBookmarked ? "Remove this bookmark (⌘D)" : "Bookmark the current caret location (⌘D)")
                Menu("Bookmark Pane Actions", systemImage: "ellipsis") {
                    Button("Hide Bookmarks") { model.inspectorPanes.bookmarks = false }
                }
                .labelStyle(.iconOnly).menuStyle(.borderlessButton).fixedSize()
            }
            if let error = bookmarks.navigationError {
                ContextStatusLine(text: "Bookmark unavailable", detail: error, systemImage: "exclamationmark.triangle")
                    .padding(.horizontal, Theme.inset)
            }
            if bookmarks.entries.isEmpty {
                ContextStatusLine(text: bookmarks.scope == nil ? "No Repository" : "No Bookmarks",
                                  detail: bookmarks.scope == nil ? "Open a repository to see its bookmarks." : "Bookmark a source location with ⌘D. Drag bookmarks to assign ⌘0–⌘9.",
                                  systemImage: "bookmark")
                    .padding(Theme.inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                List(selection: $bookmarks.selectedID) {
                    ForEach(bookmarks.rows) { row in
                        Button { model.goToBookmark(id: row.id) } label: {
                            BookmarkRow(bookmark: row.bookmark, slot: row.slot)
                        }
                        .buttonStyle(.plain)
                        .tag(row.id)
                        .contextMenu { BookmarkContextMenu(bookmark: row.bookmark, slot: row.slot) }
                    }
                    .onMove(perform: bookmarks.move)
                    .onDelete(perform: remove)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .onKeyPress(.return, action: openSelection)
                .accessibilityHint("Drag to reorder bookmarks. The first ten use Command 0 through Command 9.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InspectorSectionBackground(section: .bookmarks))
        .disabled(model.isOpening || model.pullRequests.isLoading)
    }

    private var scopeTitle: String? {
        guard let scope = model.bookmarks.scope else { return nil }
        return scope.pullRequest.map { "PR #\($0)" } ?? "Checkout"
    }

    private func openSelection() -> KeyPress.Result {
        guard let id = model.bookmarks.selectedID else { return .ignored }
        model.goToBookmark(id: id)
        return .handled
    }

    private func remove(_ offsets: IndexSet) {
        let ids = offsets.compactMap { model.bookmarks.entries.indices.contains($0) ? model.bookmarks.entries[$0].id : nil }
        for id in ids { model.bookmarks.remove(id) }
    }
}
