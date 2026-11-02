import SwiftUI

/// A few numbered lines of real source on the text background, dedented as a
/// block. One line can be emphasized (the call site or the definition).
struct CodeSnippetView: View {
    let lines: [SnippetLine]
    let emphasizedLine: Int?
    var isTruncated = false

    var body: some View {
        let dedented = SnippetLine.dedent(lines)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(dedented) { line in
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
                    Text(line.number, format: .number.grouping(.never))
                        .font(Theme.Fonts.snippetLineNumber)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: Theme.snippetLineNumberWidth, alignment: .trailing)
                    Text(line.text)
                        .font(line.number == emphasizedLine ? Theme.Fonts.codeSnippetEmphasis : Theme.Fonts.codeSnippet)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if isTruncated {
                Text("…")
                    .font(Theme.Fonts.codeSnippet)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, Theme.snippetLineNumberWidth + Theme.spacing)
                    .accessibilityLabel("More source follows")
            }
        }
        .padding(Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: Theme.snippetCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.snippetCornerRadius).strokeBorder(.separator)
        }
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilitySource)
    }

    /// The source itself, one numbered line at a time, so VoiceOver reads
    /// the preview rather than only its range.
    private var accessibilitySource: String {
        lines.map { "Line \($0.number): \($0.text.trimmingCharacters(in: .whitespaces))" }.joined(separator: "\n")
    }

    private var accessibilityTitle: String {
        guard let first = lines.first?.number, let last = lines.last?.number else { return "Source preview" }
        return first == last ? "Source preview, line \(first)" : "Source preview, lines \(first) to \(last)"
    }
}
