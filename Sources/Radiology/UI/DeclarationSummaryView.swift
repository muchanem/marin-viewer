import SwiftUI

/// Pinned above the reference list: one line naming what the caret is inside
/// (or whose references were requested). The signature is behind the
/// disclosure triangle.
struct DeclarationSummaryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var context = model.context
        Group {
            if let explicit = context.explicitReferences {
                InspectorSymbolSummary(name: explicit.displayName, kind: explicit.kind.name,
                                 systemImage: explicit.kind.systemImage) {
                    EmptyView()
                }
            } else if let declaration = context.declaration {
                DisclosureGroup(isExpanded: $context.isDeclarationExpanded) {
                    SignatureText(signature: declaration.signature, lineLimit: DeclarationContext.maxSignatureLines)
                    .padding(.top, Theme.spacing / 2)
                } label: {
                    InspectorSymbolSummary(name: declaration.declaration.name, kind: declaration.displayKind,
                                     systemImage: OutlineRow.icon(for: declaration.declaration.kind)) {
                        Text("·").foregroundStyle(.secondary).accessibilityHidden(true)
                        Button("\((declaration.path as NSString).lastPathComponent):\(declaration.line)", action: model.revealDeclaration)
                            .buttonStyle(.link)
                            .help("Go to \(declaration.declaration.name), line \(declaration.line). Back returns to the caret.")
                            .accessibilityLabel("Go to line \(declaration.line)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}
