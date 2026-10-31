import SwiftUI

/// Persistent pane controls remain available even when every pane is disabled.
/// Active panes share the available height through native split dividers.
struct ContextInspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ContextRegionHeader(title: "Context", detail: nil) { InspectorPanesMenu() }
                .padding(.bottom, Theme.spacing / 2)
            Divider()
            InspectorPaneStack(panes: model.inspectorPanes.visiblePanes(hasTrait: model.context.implementations.symbol != nil))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .inspectorColumnWidth(min: Theme.inspectorMinWidth, ideal: Theme.inspectorIdealWidth, max: Theme.inspectorMaxWidth)
    }
}
