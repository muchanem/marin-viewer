import SwiftUI

struct ReviewChangeStatus: View {
    let status: FileChange.Status
    /// The viewer's Changes tab shows a letter for every status (A, M, D, R, C).
    var showsLetter = false

    var body: some View {
        Group {
            if status == .modified || (showsLetter && letter != nil) {
                Text(letter ?? "M").font(Theme.Fonts.changeStatus)
            } else {
                Image(systemName: status.systemImage).font(Theme.Fonts.meta)
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 18)
        .accessibilityLabel(status.title)
    }

    private var letter: String? {
        switch status {
        case .added: "A"
        case .modified: "M"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .other: nil
        }
    }
}
