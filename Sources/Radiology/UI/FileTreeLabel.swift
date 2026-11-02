import SwiftUI

/// A Files row: name, PR change dot, and Reveal in Finder.
struct FileTreeLabel: View {
    @Environment(AppModel.self) private var model
    let title: String
    let path: String
    let isDirectory: Bool
    let root: URL

    var body: some View {
        // A changed path in a review carries a small accent dot; directories
        // containing changes are not marked, to keep the tree quiet.
        let changed = !isDirectory && model.review?.change(touching: path) != nil
        let currentBefore = !isDirectory && model.source?.path == path && model.source?.revision == .before
        HStack(spacing: Theme.spacing / 2) {
            Label(title, systemImage: isDirectory ? "folder" : "doc.text")
                .lineLimit(1).truncationMode(.tail)
            if changed {
                Circle().fill(.tint).frame(width: 6, height: 6)
                    .accessibilityLabel("Changed in this pull request")
            }
            if currentBefore {
                Text("Before").font(Theme.Fonts.inspectorMetadata).foregroundStyle(.secondary)
            }
        }
        .tag(path)
        .contextMenu {
            if !isDirectory { ViewerFileMenu(path: path) }
            Button("Reveal in Finder", action: revealInFinder)
        }
    }

    private func revealInFinder() {
        let root = !isDirectory && model.source?.path == path && model.source?.revision == .before
            ? model.review?.beforeRoot ?? root : root
        NSWorkspace.shared.activateFileViewerSelecting([root.appending(path: path)])
    }
}
