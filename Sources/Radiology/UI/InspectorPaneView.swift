import SwiftUI

struct InspectorPaneView: View {
    let pane: InspectorPane

    var body: some View {
        VStack(spacing: 0) {
            switch pane {
            case .references: DeclarationRegionView()
            case .definition, .implementations: ContextDetailPane()
            case .bookmarks: BookmarksPane()
            }
        }
        .frame(minHeight: pane.minimumHeight, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("context-pane-\(pane.rawValue)")
    }
}
