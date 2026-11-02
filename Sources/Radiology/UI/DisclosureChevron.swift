import SwiftUI

/// A list-row disclosure triangle, as in Finder and Xcode outlines. Toggling
/// it only reveals detail; it never navigates or moves the source caret.
struct DisclosureChevron: View {
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        Button(isExpanded ? "Hide Context" : "Show Context", systemImage: "chevron.right", action: toggle)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(Theme.Fonts.disclosure)
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
            .frame(width: Theme.disclosureWidth)
            .contentShape(.rect)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}
