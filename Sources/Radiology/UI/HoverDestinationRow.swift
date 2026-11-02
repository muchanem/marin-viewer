import SwiftUI

/// The whole named entry is a button when a real indexed destination exists.
/// External rows remain plain unavailable content, never a guessed action.
struct HoverDestinationRow: View {
    let name: String
    let systemImage: String
    let detail: String
    var via: String = ""
    let definition: SemanticPosition?
    let navigate: (SemanticPosition?, String) -> Void

    var body: some View {
        let label = HStack(alignment: .firstTextBaseline, spacing: Theme.spacing / 2) {
            Image(systemName: systemImage).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(name)
                .font(Theme.Fonts.body.weight(.semibold))
                .foregroundStyle(definition == nil ? Color.primary : Color.accentColor)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(2)
            if !via.isEmpty {
                Text("via \(via)")
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.spacing / 2)
            Text(detail)
                .font(Theme.Fonts.meta)
                .foregroundStyle(definition == nil ? Color.secondary : Color.accentColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if let definition {
            Button { navigate(definition, name) } label: { label }
                .buttonStyle(.plain)
                .help("Go to \(name) in \(definition.path). Back returns to the caret.")
                .accessibilityLabel("Go to \(name), \(definition.path) line \(definition.range.startLine + 1)")
        } else {
            label
                .help("Defined outside this repository; no indexed definition to open.")
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(name), no indexed definition available")
        }
    }
}
