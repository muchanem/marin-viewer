import SwiftUI

/// Related search/navigation actions replace several competing toolbar icons.
/// Their existing menu-bar keyboard shortcuts remain the single registrations.
struct SourceSearchMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Search", systemImage: "magnifyingglass") {
            Button("Go to File…", systemImage: "doc.text.magnifyingglass", action: model.showFiles)
                .help("Go to File (⌘K)")
            Button("Go to Symbol…", systemImage: "function", action: model.showSymbolSearch)
                .help("Go to Symbol (⌘T)")
            Divider()
            Button("Search Repository", systemImage: "magnifyingglass", action: model.showSearch)
                .help("Search Repository (⇧⌘F)")
        }
        .labelStyle(.iconOnly)
        .menuIndicator(.hidden)
        .disabled(model.repository == nil)
        .help("Go to File, Go to Symbol, or Search Repository")
    }
}
