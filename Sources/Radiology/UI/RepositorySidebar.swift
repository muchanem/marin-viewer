import SwiftUI

struct RepositorySidebar: View {
    @Environment(AppModel.self) private var model
    /// Present in viewer windows; with a wordbase PR open the tabs become the viewer's.
    @Environment(ViewerStore.self) private var viewer: ViewerStore?
    var body: some View {
        @Bindable var model = model
        let viewerPR = viewer?.isReviewing == true
        VStack(spacing: 0) {
            if let repository = model.repository {
                SidebarModeTabs(modes: BrowserMode.available(reviewing: model.isReviewing, viewerPR: viewerPR), selection: $model.mode)
                switch model.mode {
                case .changes:
                    if viewerPR { ViewerChangesView() } else { ReviewChangesView() }
                case .files:
                    if viewerPR { ViewerFocusedFilesView() } else { RepositoryFilesView(repository: repository) }
                case .codePaths: CodePathsSidebar()
                case .search: RepositorySearchView()
                case .steps: ViewerCodePathSidebar()
                }
                Divider()
                if viewerPR {
                    ViewerSidebarFooter(mode: model.mode, searchMatches: model.matches.count)
                } else {
                    HStack {
                        Text(footer(repository)).font(Theme.Fonts.meta).foregroundStyle(.secondary).lineLimit(2)
                            .help(footer(repository))
                        Spacer()
                        Image(systemName: repository.isGit ? "point.3.connected.trianglepath.dotted" : "folder")
                            .help(model.review.map { "Pull request head: \($0.headSHA)" }
                                  ?? (repository.isGit ? "Git ignore rules applied" : "Folder browsing"))
                            .accessibilityLabel(model.review.map { "Pull request head \($0.headSHA.prefix(10))" }
                                                ?? (repository.isGit ? "Git repository" : "Folder"))
                    }.padding(Theme.inset)
                }
            } else {
                ContentUnavailableView("Repository", systemImage: "folder", description: Text("Open a folder to explore its files."))
            }
        }
        .onChange(of: model.isReviewing) { if !model.isReviewing, !viewerPR, model.mode == .changes { model.mode = .files } }
        .onChange(of: viewerPR) { if !viewerPR, model.mode == .steps { model.mode = .files } }
    }

    /// Visible count, named filter state, and any hidden-open-file notice.
    private func footer(_ repository: RepositorySnapshot) -> String {
        if model.mode == .codePaths {
            let count = model.codePaths.paths.count
            return "\(count) \(count == 1 ? "code path" : "code paths")"
        }
        let filters = [model.sourceFilters.sourceFilesOnly ? "Source only" : nil,
                       model.sourceFilters.hidesTests ? "Tests hidden" : nil].compactMap { $0 }
        if model.mode == .changes, let review = model.review {
            let visible = ReviewChangesPresentation(changes: review.changes, filters: model.sourceFilters)
            var text = ([visible.fileCountLabel] + filters).joined(separator: " · ")
            if let source = model.source, visible.selectionID(path: source.path, revision: source.revision) == nil {
                text += " · open file not in visible changes"
            }
            return text
        }
        let presentation = model.mode == .files ? model.filesSidebarPresentation : nil
        let total = repository.files.count + (presentation?.currentFileOutsideSnapshot == true ? 1 : 0)
        let visible = model.visibleFileCount + (presentation?.addsTreeException == true ? 1 : 0)
        var text = model.sourceFilters.isActive
            ? "\(visible) of \(total) files"
            : "\(total) files"
        if !filters.isEmpty { text += " · \(filters.joined(separator: " · "))" }
        if presentation?.addsTreeException == true || (!model.fileQuery.isEmpty && presentation?.addsFilterException == true) {
            text += " · current file revealed"
        }
        return text
    }
}
