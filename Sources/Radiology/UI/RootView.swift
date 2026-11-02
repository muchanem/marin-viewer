import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    // Present in viewer windows (see plans/shell.md): an open wordbase PR swaps the detail,
    // toolbar and inspector for the viewer's, and ⌥⌘I toggles the session panel.
    @Environment(ViewerStore.self) private var viewer: ViewerStore?
    @Environment(ViewerWindowModel.self) private var window: ViewerWindowModel?
    @State private var isContextPresented = true
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var isPullRequestErrorPresented = false
    var body: some View {
        @Bindable var model = model
        let viewerPR = viewer?.isReviewing == true
        let isPanelPresented = panelBinding
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            // The column width must be the sidebar's outermost modifier: after it,
            // `.toolbar(removing:)` hides the width from the split view, which then opens the
            // sidebar at 144 points.
            RepositorySidebar()
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: Theme.sidebarMinWidth, ideal: Theme.sidebarIdealWidth, max: Theme.sidebarMaxWidth)
        } detail: {
            Group { if viewerPR { ViewerMainView() } else { ReaderDetail() } }
                .navigationTitle(model.attachedRoot?.lastPathComponent ?? model.repository?.root.lastPathComponent ?? "Marin Viewer")
                .modifier(ReaderToolbarTitleVisibility())
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    if viewerPR {
                        ViewerToolbar(sidebarVisibility: $sidebarVisibility, isPanelPresented: isPanelPresented)
                    } else {
                        ReaderToolbar(sidebarVisibility: $sidebarVisibility, isContextPresented: isPanelPresented)
                    }
                }
        }
        .inspector(isPresented: isPanelPresented) {
            if viewerPR { ViewerPanel() } else { ContextInspectorView() }
        }
        .focusedSceneValue(\.isContextPresented, isPanelPresented)
        .onChange(of: model.inspectorPanes.enabledCount) { oldCount, newCount in
            if newCount > oldCount { isPanelPresented.wrappedValue = true }
        }
        .onChange(of: model.inspectorRevealRevision) { isPanelPresented.wrappedValue = true }
        .onChange(of: model.sidebarRevealRevision) { sidebarVisibility = .all }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .files: QuickFilePicker()
            case .line: GoToLineSheet()
            case .symbols: SymbolSearchSheet()
            case .pullRequest: PullRequestNumberSheet()
            case .codePath: CodePathImportSheet()
            case .keyboardHelp: KeyboardShortcutsHelpView()
            }
        }
        .onChange(of: model.pullRequests.loadError) { _, error in
            isPullRequestErrorPresented = error != nil
        }
        .alert(model.pullRequests.failedRefresh ? "Could Not Refresh Pull Request" : "Could Not Open Pull Request", isPresented: $isPullRequestErrorPresented,
               presenting: model.pullRequests.loadError) { _ in
            Button("Try Again") { model.pullRequests.retryFailedReview() }
            Button("Choose Number…") {
                model.pullRequests.loadError = nil
                model.showPullRequestNumber()
            }
            Button("Cancel", role: .cancel) { model.pullRequests.loadError = nil }
        } message: { error in
            Text(error)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
            model.openRepository(isDirectory.boolValue ? url : url.deletingLastPathComponent())
            return true
        }
        .modifier(ViewerWindowChrome())
    }

    /// The viewer window's panel, or Radiology's own Context inspector state.
    private var panelBinding: Binding<Bool> {
        guard let window else { return $isContextPresented }
        return Binding(get: { window.isPanelPresented }, set: { window.isPanelPresented = $0 })
    }
}
