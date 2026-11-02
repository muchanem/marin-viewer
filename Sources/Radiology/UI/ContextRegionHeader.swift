import SwiftUI

/// The label row above each Context region.
struct ContextRegionHeader<Accessory: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
            Text(title)
                .font(Theme.Fonts.regionTitle)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(Theme.Fonts.meta)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            accessory
        }
        .padding(.horizontal, Theme.inset)
        .padding(.top, Theme.spacing / 2)
        .frame(minHeight: Theme.contextHeaderHeight)
    }
}

extension ContextRegionHeader where Accessory == EmptyView {
    init(title: String, detail: String? = nil) {
        self.init(title: title, detail: detail) { EmptyView() }
    }
}
