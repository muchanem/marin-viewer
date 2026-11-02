import SwiftUI

struct TraitImplementationsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var pane = model.context.implementations
        VStack(spacing: 0) {
            ContextRegionHeader(title: "Trait Implementations", detail: countDetail) {
                if pane.hasGaps {
                    Label("Partial coverage", systemImage: "exclamationmark.triangle")
                        .labelStyle(.iconOnly)
                        .font(Theme.Fonts.inspectorMetadata)
                }
            }
            .help("\(pane.displayName): \(pane.count) indexed implementations, \(pane.negativeCount) negative impls. \(pane.coverageDetail)")
            List(selection: $pane.selectedID) {
                if let error = pane.navigationError {
                    ContextStatusLine(text: "Implementation unavailable", detail: error, systemImage: "exclamationmark.triangle")
                }
                if !pane.isPrepared {
                    ContextStatusLine(text: "Waiting for index", detail: "Implementations are prepared with the repository's semantic index.")
                } else if pane.groups.isEmpty {
                    ContextStatusLine(text: "No indexed implementations", detail: pane.coverageDetail)
                } else {
                    ForEach(pane.groups) { group in
                        ForEach(group.items) { item in
                            TraitImplementationRow(item: item) { open(item.id) }
                                .tag(item.id)
                                .listRowInsets(EdgeInsets(top: 1, leading: Theme.inset, bottom: 1, trailing: Theme.inset))
                                .listRowSeparator(.hidden)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, Theme.inspectorImplementationRowHeight)
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: TraitImplementation.ID.self) { ids in
                if let id = ids.first, ids.count == 1 {
                    Button("Go to Trait Implementation") { open(id) }
                }
            }
            .onKeyPress(.return, action: commitSelection)
            .onKeyPress(.escape, action: clearSelection)
            .accessibilityLabel("Implementations of \(pane.displayName)")
            .accessibilityHint("Click an implementation to open it. Up and Down select; Return opens the selection.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(InspectorSectionBackground(section: .implementations))
    }

    private func open(_ id: TraitImplementation.ID) {
        model.openTraitImplementation(id: id)
    }

    private var countDetail: String? {
        let pane = model.context.implementations
        guard pane.isPrepared else { return nil }
        return "\(pane.count + pane.negativeCount)"
    }

    private func commitSelection() -> KeyPress.Result {
        guard let id = model.context.implementations.selectedID else { return .ignored }
        open(id)
        return .handled
    }

    private func clearSelection() -> KeyPress.Result {
        guard model.context.implementations.selectedID != nil else { return .ignored }
        model.context.implementations.selectedID = nil
        return .handled
    }
}
