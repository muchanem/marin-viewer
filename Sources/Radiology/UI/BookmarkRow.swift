import SwiftUI

struct BookmarkRow: View {
    let bookmark: SourceBookmark
    let slot: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.label)
                    .font(Theme.Fonts.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(bookmark.path):\(bookmark.line)")
                    .font(Theme.Fonts.inspectorMetadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                if let revision = bookmark.revision {
                    Text(revision.title)
                        .font(Theme.Fonts.inspectorMetadata)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if slot < 10 {
                Text("⌘\(slot)")
                    .font(Theme.Fonts.snippetLineNumber)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .help("\(bookmark.path):\(bookmark.line), column \(bookmark.column + 1)")
        .accessibilityElement(children: .combine)
        .accessibilityHint(slot < 10 ? "Command \(slot) opens this bookmark. Drag to reorder." : "Drag into the first ten entries to assign a shortcut.")
    }
}
