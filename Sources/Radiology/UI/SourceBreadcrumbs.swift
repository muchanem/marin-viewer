import SwiftUI

struct SourceBreadcrumbs: View {
    let rootName: String
    let path: String
    let symbols: [DocumentSymbol]
    let canCollapseFunctions: Bool
    var isReviewing = false
    var canPreviousChange = false
    var canNextChange = false
    var previousChange: () -> Void = {}
    var nextChange: () -> Void = {}
    let collapseFunctions: () -> Void
    let select: (DocumentSymbol) -> Void
    var body: some View {
        HStack(spacing: Theme.spacing) {
            SourceBreadcrumbPath(rootName: rootName, path: path, symbols: symbols, select: select)
                .frame(minWidth: 0, maxWidth: .infinity)
                .frame(height: Theme.breadcrumbHeight)
                .layoutPriority(-1)
            if isReviewing {
                ChangeBlockControls(canPrevious: canPreviousChange, canNext: canNextChange,
                                    previous: previousChange, next: nextChange)
            }
            Button("Collapse Functions", systemImage: "arrow.down.right.and.arrow.up.left", action: collapseFunctions)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(width: 28, height: 28)
            .contentShape(.rect)
            .disabled(!canCollapseFunctions)
            .help("Collapse Functions")
            .accessibilityLabel("Collapse Functions")
        }
        .font(Theme.Fonts.meta)
        .padding(.horizontal, Theme.inset)
        .frame(minHeight: Theme.breadcrumbHeight)
        .accessibilityElement(children: .contain)
    }
}
