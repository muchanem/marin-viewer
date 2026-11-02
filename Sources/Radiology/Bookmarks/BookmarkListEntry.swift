import Foundation

/// Stable row identity plus the shortcut position in the current ordering.
struct BookmarkListEntry: Identifiable {
    let bookmark: SourceBookmark
    let slot: Int
    var id: UUID { bookmark.id }
}
