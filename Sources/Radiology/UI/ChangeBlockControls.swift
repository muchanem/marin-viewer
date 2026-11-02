import SwiftUI

/// Quiet source-header affordances; menu shortcuts share the same model state.
struct ChangeBlockControls: View {
    let canPrevious: Bool
    let canNext: Bool
    let previous: () -> Void
    let next: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button("Previous Changed Block", systemImage: "chevron.up", action: previous)
                .frame(width: 24, height: 24).contentShape(.rect)
                .disabled(!canPrevious)
                .help("Previous Changed Block (⌥⌘↑)")
            Button("Next Changed Block", systemImage: "chevron.down", action: next)
                .frame(width: 24, height: 24).contentShape(.rect)
                .disabled(!canNext)
                .help("Next Changed Block (⌥⌘↓)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .fixedSize()
    }
}
