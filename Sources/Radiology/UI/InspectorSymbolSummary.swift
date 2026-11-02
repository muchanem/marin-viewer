import SwiftUI

struct InspectorSymbolSummary<Location: View>: View {
    let name: String
    let kind: String
    let systemImage: String
    @ViewBuilder let location: Location

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            Image(systemName: systemImage)
                .font(Theme.Fonts.body)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(Theme.Fonts.inspectorSymbol)
                    .foregroundStyle(.primary)
                    .lineLimit(2).truncationMode(.middle)
                HStack(spacing: Theme.spacing / 2) {
                    Text(kind).foregroundStyle(.secondary)
                    location
                }
                .font(Theme.Fonts.inspectorMetadata)
                .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
