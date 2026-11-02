import SwiftUI

/// Lower Context region: the definition of the semantic symbol at the caret
/// as one line, or the file outline when the caret is on whitespace, a
/// keyword, an import, or anything the index does not describe.
struct UnderCaretRegionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ContextRegionHeader(title: model.context.underCaret == nil ? "Outline" : "Definition",
                                detail: model.context.underCaret == nil ? model.underCaretFallbackDetail : nil)
            if let underCaret = model.context.underCaret {
                ScrollView {
                    UnderCaretDetailView(context: underCaret,
                                         repeatsHeading: model.inspectorPanes.references && underCaret.symbol == (model.context.explicitReferences?.symbol ?? model.context.declaration?.identity.symbol))
                }
            } else {
                DocumentOutlineView()
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InspectorSectionBackground(section: model.context.underCaret == nil ? .outline : .definition))
    }

}
