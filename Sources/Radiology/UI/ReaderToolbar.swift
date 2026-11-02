import SwiftUI

/// Native toolbar groups: navigation/repository, PR context, and viewing tools.
struct ReaderToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    @Binding var isContextPresented: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(sidebarVisibility == .detailOnly ? "Show Navigation Sidebar" : "Hide Navigation Sidebar",
                   systemImage: "sidebar.left", action: toggleSidebar)
                .help("Show or Hide the Navigation Sidebar (⌃⌘S)")
            Button("Back", systemImage: "chevron.left", action: model.goBack)
                .disabled(!model.history.canGoBack).help("Back (⌘[)")
            Button("Forward", systemImage: "chevron.right", action: model.goForward)
                .disabled(!model.history.canGoForward).help("Forward (⌘])")
            RepositoryMenu()
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .navigation)
        }
        ToolbarItemGroup(placement: .navigation) {
            PullRequestMenu()
            if model.isReviewing {
                Button(model.pullRequests.isRefreshing ? "Refreshing PR…" : "Refresh PR",
                       systemImage: "arrow.clockwise", action: model.refreshCurrentPR)
                    .labelStyle(.iconOnly)
                    .disabled(!model.canRefreshPR)
                    .help("Refresh this pull request from GitHub (⌘R)")
            }
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: Theme.spacing) {
                SourceModePicker()
                if let control = model.revisionControl {
                    SourceRevisionPicker(control: control, setRevision: model.setRevision)
                }
            }
            .font(Theme.Fonts.body)
            .fixedSize(horizontal: true, vertical: false)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            SourceSearchMenu()
            Button(isContextPresented ? "Hide Context Inspector" : "Show Context Inspector",
                   systemImage: "sidebar.right", action: toggleContext)
                .help("Show or Hide the Context Inspector (⌥⌘I)")
        }
    }

    private func toggleSidebar() {
        sidebarVisibility = sidebarVisibility == .detailOnly ? .all : .detailOnly
    }

    private func toggleContext() { isContextPresented.toggle() }
}
