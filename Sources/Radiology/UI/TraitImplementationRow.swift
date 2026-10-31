import SwiftUI

struct TraitImplementationRow: View {
    let item: TraitImplementation
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.spacing / 2) {
                Text(item.targetType)
                    .font(Theme.Fonts.codeSnippetEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if item.isNegative {
                    Text("negative")
                        .font(Theme.Fonts.inspectorMetadata)
                        .foregroundStyle(.secondary)
                        .help("This block explicitly rules out implementation of the trait.")
                }
                Spacer(minLength: 0)
                Text("\(URL(filePath: item.path).lastPathComponent):\(item.line)")
                    .font(Theme.Fonts.snippetLineNumber)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 96, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.inspectorImplementationRowHeight - 2, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(item.path):\(item.line)\n\(item.signature)")
        .accessibilityLabel("\(item.isNegative ? "Negative implementation" : "Implementation"), \(item.path), line \(item.line): \(item.signature)")
        .accessibilityHint("Go to trait implementation")
    }
}
