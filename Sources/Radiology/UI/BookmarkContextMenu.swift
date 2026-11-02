import SwiftUI

struct BookmarkContextMenu: View {
    @Environment(AppModel.self) private var model
    let bookmark: SourceBookmark
    let slot: Int

    var body: some View {
        Button("Go to Bookmark") { model.goToBookmark(id: bookmark.id) }
        Button("Move Up") { model.bookmarks.move(bookmark.id, to: slot - 1) }
            .disabled(slot == 0)
        Button("Move Down") { model.bookmarks.move(bookmark.id, to: slot + 1) }
            .disabled(slot + 1 >= model.bookmarks.entries.count)
        Menu("Move to Shortcut") {
            ForEach(0..<min(10, model.bookmarks.entries.count), id: \.self) { position in
                Button("⌘\(position)") { model.bookmarks.move(bookmark.id, to: position) }
                    .disabled(position == slot)
            }
        }
        Divider()
        Button("Remove Bookmark", role: .destructive) { model.bookmarks.remove(bookmark.id) }
    }
}
