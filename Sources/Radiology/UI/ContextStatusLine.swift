import SwiftUI

/// One quiet line of status in the Context inspector. The short text keeps
/// the default layout scannable; the full, honest reason is the tooltip and
/// what VoiceOver reads.
struct ContextStatusLine: View {
    let text: String
    let detail: String
    var systemImage = "info.circle"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(Theme.Fonts.meta)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(detail)
            .accessibilityLabel(detail)
    }
}
