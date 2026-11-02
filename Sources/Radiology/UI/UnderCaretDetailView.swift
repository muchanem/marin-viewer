import SwiftUI

/// The symbol at the caret as one line: name, kind, and where it is defined.
/// The disclosure triangle (or Right/Left with this region focused) reveals
/// signature, docs, reference count, and the source preview. Return, the
/// location link, ⌃⌘J, or ⌘-click navigate; nothing here moves the source on
/// its own.
struct UnderCaretDetailView: View {
    @Environment(AppModel.self) private var model
    let context: UnderCaretContext
    var repeatsHeading = false

    var body: some View {
        @Bindable var contextModel = model.context
        VStack(alignment: .leading, spacing: Theme.spacing) {
            DisclosureGroup(isExpanded: $contextModel.isDefinitionExpanded) {
                DefinitionDetailsView(context: context)
                    .padding(.top, Theme.spacing / 2)
            } label: {
                if repeatsHeading {
                    DefinitionLocationView(context: context)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.target.displayName)
                            .font(Theme.Fonts.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2).truncationMode(.middle)
                        DefinitionLocationView(context: context)
                            .font(Theme.Fonts.meta)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.inset)
        .padding(.vertical, Theme.spacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusable()
        .onKeyPress(.return, action: activateDefinition)
        .onKeyPress(.rightArrow) { setExpanded(true) }
        .onKeyPress(.leftArrow) { setExpanded(false) }
        .accessibilityHint(context.destination == nil ? "" : "Press Return to go to the definition.")
    }

    private func activateDefinition() -> KeyPress.Result {
        guard context.destination != nil else { return .ignored }
        model.goToUnderCaretDefinition()
        return .handled
    }

    private func setExpanded(_ expanded: Bool) -> KeyPress.Result {
        guard model.context.isDefinitionExpanded != expanded else { return .ignored }
        model.context.isDefinitionExpanded = expanded
        return .handled
    }
}
