import SwiftUI

/// The sidebar's Files mode: filter field and the
/// filtered tree (or the filter field's flat results).
struct RepositoryFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    let repository: RepositorySnapshot

    var body: some View {
        @Bindable var model = model
        let presentation = model.filesSidebarPresentation
        TextField("Filter files", text: $model.fileQuery)
            .textFieldStyle(.roundedBorder)
            .onChange(of: model.fileQuery) { model.filterFiles() }
            .padding(.horizontal, Theme.inset)
        ScrollViewReader { proxy in
            Group {
                if model.fileQuery.isEmpty, (presentation?.tree ?? model.fileTree).isEmpty, !repository.files.isEmpty {
                    ContentUnavailableView {
                        Label("No Files to Show", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("The current filters exclude every file in this repository.")
                    } actions: {
                        Button("Show All Files", action: model.clearSourceFilters)
                    }
                } else if !model.fileQuery.isEmpty, (presentation?.files ?? model.filteredFiles).isEmpty {
                    ContentUnavailableView {
                        Label("No Matching Files", systemImage: "magnifyingglass")
                    } description: {
                        Text(model.sourceFilters.isActive
                             ? "No files matching “\(model.fileQuery)” pass the current filters."
                             : "No files match “\(model.fileQuery)”.")
                    } actions: {
                        if model.sourceFilters.isActive {
                            Button("Show All Files", action: model.clearSourceFilters)
                        }
                    }
                } else {
                    List(selection: $selection) {
                        if model.fileQuery.isEmpty {
                            ForEach(presentation?.tree ?? model.fileTree) { node in
                                FileTreeRow(node: node, expansion: model.fileTreeExpansion, root: repository.root)
                            }
                        } else {
                            ForEach(presentation?.files ?? model.filteredFiles) { file in
                                FileTreeLabel(title: file.path, path: file.path, isDirectory: false, root: repository.root)
                                    .id(file.path)
                            }
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .task(id: FilesSidebarRevealIdentity(root: repository.root, path: model.selectedPath, loadedPath: model.source?.path,
                                               navigation: model.navigationRevision, query: model.fileQuery, filters: model.sourceFilters)) {
                await revealCurrentFile(using: proxy)
            }
        }
        .frame(maxHeight: .infinity)
        .onChange(of: selection) { openSelection() }
        .onChange(of: model.selectedPath, initial: true) { selection = model.selectedPath }
    }

    private func revealCurrentFile(using proxy: ScrollViewProxy) async {
        guard model.mode == .files, let path = model.filesSidebarPresentation?.currentFile?.path,
              repository.root == model.repository?.root else { return }
        model.fileTreeExpansion.reveal(path)
        selection = path
        // Let disclosures materialize their child rows before asking the
        // native List to locate and center the leaf. Cancellation rejects a
        // superseded navigation or a switch away from Files.
        await Task.yield()
        guard !Task.isCancelled, model.mode == .files, repository.root == model.repository?.root,
              path == model.selectedPath else { return }
        proxy.scrollTo(path, anchor: .center)
    }

    private func openSelection() {
        guard repository.root == model.repository?.root, let path = selection, path != model.selectedPath,
              repository.files.contains(where: { $0.path == path }) else { return }
        model.openFile(path)
    }
}
