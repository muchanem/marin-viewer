import SwiftUI

struct BookmarkCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Bookmarks") {
            Button(model.isCurrentLocationBookmarked ? "Remove Bookmark" : "Bookmark Location", action: model.toggleCurrentBookmark)
                .keyboardShortcut("d")
                .disabled(!model.canBookmarkCurrentLocation)
            Divider()
            ForEach(0..<10, id: \.self) { slot in
                Button(model.bookmarks.bookmark(at: slot)?.label ?? "Bookmark \(slot)") { model.goToBookmark(slot: slot) }
                    .keyboardShortcut(KeyEquivalent(Character(String(slot))))
                    .disabled(model.bookmarks.bookmark(at: slot) == nil || model.repository == nil || model.isOpening || model.pullRequests.isLoading)
            }
        }
    }
}
