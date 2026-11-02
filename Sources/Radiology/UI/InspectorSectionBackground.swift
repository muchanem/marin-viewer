import SwiftUI

/// Subtle section cues use dynamic system colors; headings/dividers carry meaning.
struct InspectorSectionBackground: View {
    enum Section {
        case symbol, references, definition, outline, bookmarks, implementations
    }

    let section: Section
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        color.opacity(colorScheme == .dark ? 0.055 : 0.025)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch section {
        case .symbol: Color(nsColor: .systemBlue)
        case .references: Color(nsColor: .systemTeal)
        case .definition: Color(nsColor: .systemPurple)
        case .outline: Color(nsColor: .secondaryLabelColor)
        case .bookmarks: Color(nsColor: .systemOrange)
        case .implementations: Color(nsColor: .systemIndigo)
        }
    }
}
