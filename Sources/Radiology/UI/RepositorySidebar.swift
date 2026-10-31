import SwiftUI

struct RepositorySidebar: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let repository = model.repository {
                SidebarModeTabs(modes: BrowserMode.available(reviewing: model.isReviewing), selection: $model.mode)
                switch model.mode {
                case .changes:
                    ReviewChangesView()
                case .files:
                    RepositoryFilesView(repository: repository)
                case .codePaths: CodePathsSidebar()
                case .search: RepositorySearchView()
                }
                Divider()
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
            } else {
                ContentUnavailableView("Repository", systemImage: "folder", description: Text("Open a folder to explore its files."))
            }
        }
        .onChange(of: model.isReviewing) { if !model.isReviewing, model.mode == .changes { model.mode = .files } }
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
