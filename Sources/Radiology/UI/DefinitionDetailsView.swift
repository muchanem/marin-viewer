import SwiftUI

/// Revealed only by expanding the definition row: what the index records
/// (signature, documentation, counts) and the real source preview.
struct DefinitionDetailsView: View {
    @Environment(AppModel.self) private var model
    let context: UnderCaretContext

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(facts)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
            if !context.signature.isEmpty {
                Text(context.signature)
                    .font(Theme.Fonts.codeSnippet)
                    .lineLimit(DeclarationContext.maxSignatureLines)
                    .textSelection(.enabled)
                    .accessibilityLabel("Signature")
                    .accessibilityValue(context.signature)
            }
            if let documentation = context.documentation {
                Text(documentation)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            if context.isLocal {
                if let line = context.localDefinitionLine, !context.target.isOnDefinition {
                    CodeSnippetView(lines: [line], emphasizedLine: nil)
                }
            } else {
                DefinitionPreviewPhaseView(phase: model.context.preview,
                                           emphasizedLine: context.destination.map { $0.range.startLine + 1 })
            }
        }
    }

    /// One line of index facts: kind, then counts and scope.
    private var facts: String {
        var parts = [context.isLocal ? "Local \(context.target.kind.name.lowercased())" : context.target.kind.name]
        if context.isLocal {
            parts.append(context.fileOccurrenceCount == 1 ? "1 use in this file" : "\(context.fileOccurrenceCount) uses in this file")
            if let enclosing = context.enclosingName { parts.append("in \(enclosing)") }
        } else {
            parts.append(context.target.referenceCount == 1 ? "1 reference" : "\(context.target.referenceCount) references")
            if context.target.definitions.count > 0, context.target.isOnDefinition {
                parts.append("\(context.target.definitions.count) more definitions")
            }
            if let package = context.externalPackage { parts.append(package) }
        }
        return parts.joined(separator: " · ")
    }
}
