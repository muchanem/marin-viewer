import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var isContextPresented = true
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var isPullRequestErrorPresented = false
    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            RepositorySidebar()
                .navigationSplitViewColumnWidth(min: Theme.sidebarMinWidth, ideal: Theme.sidebarIdealWidth, max: Theme.sidebarMaxWidth)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ReaderDetail()
                .navigationTitle(model.attachedRoot?.lastPathComponent ?? model.repository?.root.lastPathComponent ?? "Radiology")
                .modifier(ReaderToolbarTitleVisibility())
                .toolbar(removing: .sidebarToggle)
                .toolbar {
                    ReaderToolbar(sidebarVisibility: $sidebarVisibility, isContextPresented: $isContextPresented)
                }
        }
        .inspector(isPresented: $isContextPresented) {
            ContextInspectorView()
        }
        .focusedSceneValue(\.isContextPresented, $isContextPresented)
        .onChange(of: model.inspectorPanes.enabledCount) { oldCount, newCount in
            if newCount > oldCount { isContextPresented = true }
        }
        .onChange(of: model.inspectorRevealRevision) { isContextPresented = true }
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
    }

}
