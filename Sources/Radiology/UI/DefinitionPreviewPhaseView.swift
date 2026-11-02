import SwiftUI

struct DefinitionPreviewPhaseView: View {
    let phase: ContextModel.PreviewPhase
    let emphasizedLine: Int?

    var body: some View {
        switch phase {
        case .none:
            EmptyView()
        case .loading:
            ProgressView("Loading definition…")
                .controlSize(.small)
                .font(Theme.Fonts.meta)
        case .loaded(let preview):
            CodeSnippetView(lines: preview.lines, emphasizedLine: emphasizedLine, isTruncated: preview.isTruncated)
        case .unavailable(let message):
            Label(message, systemImage: "info.circle")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
        }
    }
}
