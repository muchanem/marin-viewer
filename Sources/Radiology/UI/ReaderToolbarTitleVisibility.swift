import SwiftUI

/// Keep the repository as the window's identity, while its native menu supplies
/// the visible toolbar label. macOS 14 retains its system title presentation.
struct ReaderToolbarTitleVisibility: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
