import SwiftUI
import ViewerCore

/// The context menu every file row shares (DESIGN.md §2): ask about it, open it in a new code
/// window, show it whole. Outside a viewer window it adds nothing, so Radiology's own rows keep
/// their menus unchanged.
struct ViewerFileMenu: View {
    @Environment(ViewerStore.self) private var store: ViewerStore?
    @Environment(ViewerWindowModel.self) private var window: ViewerWindowModel?
    let path: String

    var body: some View {
        if let store, store.isReviewing || window?.kind == .secondary {
            Button("Ask About \(URL(filePath: path).lastPathComponent)") {
                store.ask(chip(store), from: window)
            }
            .keyboardShortcut(">", modifiers: .command)
            Button("Open in New Window") { store.openInNewWindow(path: path) }
            if store.isReviewing, store.pr?.change(path: path) != nil {
                Button(store.wholeFilePaths.contains(path) ? "Show Changes Only" : "Show Whole File") {
                    store.toggleWholeFile(path)
                    store.open(path: path)
                }
            }
            Divider()
        }
    }

    private func chip(_ store: ViewerStore) -> Chip {
        ChipFactory.file(path, commit: store.pr?.head ?? "", shortener: store.shortener)
    }
}

extension View {
    /// Records `chip` as the window's ⌘> target when the row is clicked.
    func viewerAskTarget(_ chip: Chip?, in window: ViewerWindowModel?) -> some View {
        simultaneousGesture(TapGesture().onEnded { if let chip { window?.lastAskTarget = chip } })
    }
}
