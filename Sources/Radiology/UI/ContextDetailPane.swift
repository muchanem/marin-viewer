import SwiftUI

/// The middle inspector pane shows implementations for a trait context and
/// definition/outline otherwise. Existing native dividers remain stable.
struct ContextDetailPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            if model.inspectorPanes.implementations, model.context.implementations.symbol != nil {
                TraitImplementationsPane()
            } else {
                UnderCaretRegionView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
