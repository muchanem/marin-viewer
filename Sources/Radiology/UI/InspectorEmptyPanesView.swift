import SwiftUI

struct InspectorEmptyPanesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text(model.inspectorPanes.enabledCount == 0 ? "No panes enabled" : "No panes for this context")
                .font(Theme.Fonts.heading)
                .foregroundStyle(.primary)
            Text(model.inspectorPanes.enabledCount == 0
                 ? "Choose panes from the Panes menu above."
                 : "Implementations appear when examining a Rust trait.")
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show All Panes", action: model.showAllInspectorPanes)
                .controlSize(.small)
        }
        .padding(Theme.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
