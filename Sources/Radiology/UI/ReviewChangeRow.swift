import SwiftUI

/// Preserve the two-line row; give the name priority over path and counts.
struct ReviewChangeRow: View {
    let change: FileChange
    var isSelected = false
    /// Viewer options: a letter for every status, and a dot for a draft review note.
    var showsStatusLetter = false
    var hasDraftNote = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            ReviewChangeStatus(status: change.status, showsLetter: showsStatusLetter)
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(filePath: change.path).lastPathComponent)
                    .font(Theme.Fonts.body)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.middle)
                Text(directory)
                    .font(Theme.Fonts.changeDetail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if hasDraftNote {
                Circle().fill(Color.viewerNote).frame(width: 6, height: 6).padding(.top, 6)
                    .help("A draft review note is on this file")
                    .accessibilityLabel("Draft review note")
            }
            Group {
                if let additions = change.additions, let deletions = change.deletions {
                    Text("+\(additions) −\(deletions)")
                        .monospacedDigit()
                        .accessibilityLabel("\(additions) added, \(deletions) removed")
                } else {
                    Text("binary")
                }
            }
            .font(Theme.Fonts.changeDetail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: Theme.changeCountMinWidth, alignment: .trailing)
            .padding(.top, 2)
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
        .overlay(alignment: .leading) {
            Capsule().fill(.tint).frame(width: 2, height: 24)
                .offset(x: -6).opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    private var directory: String {
        let directory = (change.path as NSString).deletingLastPathComponent
        if let old = change.oldPath, old != change.path { return "from \(old)" }
        return directory.isEmpty ? "/" : directory
    }
}
