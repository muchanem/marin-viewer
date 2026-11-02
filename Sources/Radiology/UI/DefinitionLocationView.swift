import SwiftUI

/// The trailing part of the one-line definition row: a link to the
/// definition, "here", or the external package — never a sentence.
struct DefinitionLocationView: View {
    @Environment(AppModel.self) private var model
    let context: UnderCaretContext

    var body: some View {
        if context.target.isOnDefinition {
            HStack(spacing: Theme.spacing) {
                if let buffer = model.source, buffer.path == context.identity.path {
                    Text("\((buffer.path as NSString).lastPathComponent):\(buffer.line(atByte: context.identity.occurrence.lowerBound))")
                        .foregroundStyle(.primary)
                        .lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Text("Here").font(Theme.Fonts.inspectorMetadata).foregroundStyle(.secondary)
            }
            .help(context.target.definitions.isEmpty ? "Defined here"
                  : "Defined here and in \(context.target.definitions.count) other places")
        } else if let destination = context.destination {
            Button(locationText(destination), action: model.goToUnderCaretDefinition)
                .buttonStyle(.link)
                .help("Go to definition in \(destination.path) (Return, ⌃⌘J, or ⌘-click). Back returns to the caret.")
        } else if let package = context.externalPackage?.split(separator: " ").first {
            Text(package)
                .foregroundStyle(.secondary)
                .help("Defined in \(context.externalPackage ?? String(package)), outside this repository")
        } else if context.isDefinedOutsideRepository {
            Text("external")
                .foregroundStyle(.secondary)
                .help("Defined outside this repository")
        }
    }

    private func locationText(_ position: SemanticPosition) -> String {
        let line = position.range.startLine + 1
        let more = context.target.definitions.count > 1 ? " +\(context.target.definitions.count - 1)" : ""
        return "\((position.path as NSString).lastPathComponent):\(line)\(more)"
    }
}
