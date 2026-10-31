import SwiftUI

/// The middle slot is contextual, so zero to four physical panes are active.
/// Omitted panes leave no empty split children or unused height behind.
struct InspectorPaneStack: View {
    let panes: [InspectorPane]

    var body: some View {
        switch panes.count {
        case 4:
            VSplitView {
                InspectorPaneView(pane: panes[0])
                InspectorPaneStack(panes: Array(panes.dropFirst()))
                    .frame(minHeight: panes.dropFirst().reduce(2) { $0 + $1.minimumHeight }, maxHeight: .infinity)
            }
        case 3:
            VSplitView {
                InspectorPaneView(pane: panes[0])
                VSplitView {
                    InspectorPaneView(pane: panes[1])
                    InspectorPaneView(pane: panes[2])
                }
                .frame(minHeight: panes[1].minimumHeight + panes[2].minimumHeight + 1,
                       maxHeight: .infinity)
            }
        case 2:
            VSplitView {
                InspectorPaneView(pane: panes[0])
                InspectorPaneView(pane: panes[1])
            }
        case 1:
            InspectorPaneView(pane: panes[0])
        default:
            InspectorEmptyPanesView()
        }
    }
}
