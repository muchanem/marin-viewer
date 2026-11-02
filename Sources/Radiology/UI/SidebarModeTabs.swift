import SwiftUI

/// Compact sidebar tabs with native buttons, selected traits, and arrow navigation.
struct SidebarModeTabs: View {
    let modes: [BrowserMode]
    @Binding var selection: BrowserMode

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                SidebarModeTabRow(modes: modes, selection: $selection, showsTitles: true)
                SidebarModeTabRow(modes: modes, selection: $selection, showsTitles: false)
            }
            .padding(.horizontal, Theme.inset)
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar modes")
    }
}
