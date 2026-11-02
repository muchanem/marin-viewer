import SwiftUI

struct SourceBreadcrumbSeparator: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}
