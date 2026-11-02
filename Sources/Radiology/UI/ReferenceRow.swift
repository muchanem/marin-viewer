import SwiftUI

/// One reference or definition: a disclosure chevron, the line number, and
/// the source line with the occurrence in semibold — a single line. Expanding
/// shows the surrounding source and its incoming call tree; selection alone
/// shows nothing extra.
struct ReferenceRow: View {
    let hit: ReferenceHit
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing / 2) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing / 2) {
                DisclosureChevron(isExpanded: isExpanded, toggle: toggle)
                Text(hit.line, format: .number.grouping(.never))
                    .font(Theme.Fonts.snippetLineNumber)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: Theme.snippetLineNumberWidth, alignment: .trailing)
                Text(line)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if hit.isDefinition {
                    Text("def")
                        .font(Theme.Fonts.meta)
                        .foregroundStyle(.secondary)
                        .help("Definition")
                }
            }
            if isExpanded {
                CodeSnippetView(lines: hit.context, emphasizedLine: hit.line)
                    .padding(.leading, Theme.disclosureWidth)
                ReferenceCallTreeView(referenceID: hit.id)
                    .padding(.leading, Theme.disclosureWidth)
            }
        }
        .frame(minHeight: 24, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Line \(hit.line)\(hit.isDefinition ? ", definition" : ""): \(hit.leading)\(hit.match)\(hit.trailing)")
    }

    private var line: AttributedString {
        var leading = AttributedString(hit.leading)
        leading.font = Theme.Fonts.codeSnippet
        var match = AttributedString(hit.match)
        match.font = Theme.Fonts.codeSnippetEmphasis
        var trailing = AttributedString(hit.trailing)
        trailing.font = Theme.Fonts.codeSnippet
        return leading + match + trailing
    }
}
