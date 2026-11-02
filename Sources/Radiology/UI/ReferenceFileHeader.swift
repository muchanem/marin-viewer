import SwiftUI

struct ReferenceFileHeader: View {
    let group: ReferenceGroup

    var body: some View {
        HStack(spacing: Theme.spacing) {
            Text(group.path)
                .lineLimit(1)
                .truncationMode(.head)
                .help(group.path)
            Spacer(minLength: 0)
            Text(group.hits.count, format: .number)
                .monospacedDigit()
        }
        .font(Theme.Fonts.inspectorMetadata)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}
