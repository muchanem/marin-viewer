import SwiftUI

/// Upper Context region: the enclosing declaration (one pinned line) and the
/// SCIP references of its symbol, or explicitly requested references — one
/// line each. Up/Down selects; Right/Left (or a row's chevron) reveals or
/// hides source and callers; Return or a double-click commits. Nothing
/// here moves the source until a commit.
struct DeclarationRegionView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var context = model.context
        VStack(spacing: 0) {
            if context.explicitReferences != nil || context.declaration != nil {
                DeclarationSummaryView()
                    .padding(.horizontal, Theme.inset)
                    .padding(.vertical, Theme.inset)
                    .background(InspectorSectionBackground(section: .symbol))
                Divider()
                ContextRegionHeader(title: "References", detail: countDetail) {
                    if context.explicitReferences != nil {
                        Button("Follow Caret", action: context.followCaret)
                            .controlSize(.small)
                            .help("Show the references of the declaration around the caret again")
                    }
                }
                .background(InspectorSectionBackground(section: .references))
                List(selection: $context.selectedReferenceID) {
                    ReferenceListContent()
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
                .background(InspectorSectionBackground(section: .references))
                .contextMenu(forSelectionType: ReferenceHit.ID.self) { ids in
                    if let id = ids.first, ids.count == 1 {
                        Button("Go to Reference") { model.commitReference(id: id) }
                    }
                } primaryAction: { ids in
                    guard let id = ids.first, ids.count == 1 else { return }
                    model.commitReference(id: id)
                }
                .onKeyPress(.return, action: commitSelection)
                .onKeyPress(.escape, action: clearSelection)
                .onKeyPress(.rightArrow) { setSelectionExpanded(true) }
                .onKeyPress(.leftArrow) { setSelectionExpanded(false) }
                .accessibilityHint("Up and Down select a reference, Right shows its source and callers, and Return opens it.")
            } else {
                ContextStatusLine(text: emptyTitle, detail: emptyDescription, systemImage: "curlybraces")
                    .padding(Theme.inset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(InspectorSectionBackground(section: .symbol))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var countDetail: String? {
        guard case .loaded(let results) = model.context.references else { return nil }
        return results.referenceCount == 1 ? "1 reference" : "\(results.referenceCount) references"
    }

    private var emptyTitle: String { model.source == nil ? "No File" : "No Declaration" }

    private var emptyDescription: String {
        guard model.source != nil else { return "Open a source file to see the declaration around the caret." }
        switch model.context.declarationAbsence {
        case .noStructure:
            return model.isParsingSource ? "Reading structure…" : "This file has no parsed structure."
        case .noDeclaration:
            return "Place the caret inside a function, type, or other declaration."
        }
    }

    private func commitSelection() -> KeyPress.Result {
        guard model.canCommitSelectedRow else { return .ignored }
        model.commitSelectedReference()
        return .handled
    }

    private func setSelectionExpanded(_ expanded: Bool) -> KeyPress.Result {
        guard let id = model.context.selectedReferenceID,
              model.context.isReferenceExpanded(id) != expanded else { return .ignored }
        model.context.setReference(id, expanded: expanded)
        return .handled
    }

    private func clearSelection() -> KeyPress.Result {
        guard model.context.selectedReferenceID != nil else { return .ignored }
        model.context.selectedReferenceID = nil
        return .handled
    }
}
