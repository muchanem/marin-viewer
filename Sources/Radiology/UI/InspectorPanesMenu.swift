import SwiftUI

struct InspectorPanesMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Panes") { InspectorPaneMenuContent(model: model) }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .controlSize(.small)
            .font(Theme.Fonts.inspectorMetadata)
            .help("Choose which Context panes are enabled")
            .accessibilityLabel("Context Panes")
    }
}
