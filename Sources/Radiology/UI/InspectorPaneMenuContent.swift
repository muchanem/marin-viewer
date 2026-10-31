import SwiftUI

/// Shared native checked menu items in the inspector and View menu.
struct InspectorPaneMenuContent: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle("References", isOn: $model.inspectorPanes.references)
        Toggle("Definition / Outline", isOn: $model.inspectorPanes.definition)
        Toggle("Trait Implementations", isOn: $model.inspectorPanes.implementations)
            .help("Shown when examining a Rust trait. Otherwise the middle pane shows Definition / Outline when enabled.")
        Toggle("Bookmarks", isOn: $model.inspectorPanes.bookmarks)
        Divider()
        Button("Show All Panes", action: model.showAllInspectorPanes)
            .disabled(model.inspectorPanes.areAllEnabled)
    }
}
