import SwiftUI

struct QuickFilePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [RepositoryFile] = []
    @State private var selection = QuickFileSelection()
    @State private var totalCount = 0
    @State private var isSearching = false
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Go to file", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit(openSelection)
                    .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                Text("⌘K").font(Theme.Fonts.meta).foregroundStyle(.secondary)
            }.padding(Theme.inset * 1.5)
            Divider()
            if results.isEmpty, !isSearching {
                ContentUnavailableView(query.isEmpty ? "No Files" : "No Matches", systemImage: "doc.text.magnifyingglass",
                                       description: Text(query.isEmpty ? "This repository contains no files." : "Try fewer characters or a different order."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(results, selection: $selection.path) { file in
                        Button { open(file) } label: {
                            VStack(alignment: .leading, spacing: Theme.spacing / 2) {
                                Text(file.name).font(Theme.Fonts.body)
                                Text(directory(for: file)).font(Theme.Fonts.meta).foregroundStyle(.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .tag(file.path)
                        .id(file.path)
                    }
                    .onChange(of: selection.path) { _, path in
                        guard let path else { return }
                        // SwiftUI's macOS List is backed by NSTableView. Moving
                        // its scroll position synchronously from a selection
                        // delegate callback can re-enter the table delegate.
                        Task { @MainActor in
                            await Task.yield()
                            guard path == selection.path else { return }
                            proxy.scrollTo(path, anchor: .center)
                        }
                    }
                }
            }
            Divider()
            HStack {
                Text(footer).font(Theme.Fonts.meta).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open", action: openSelection).keyboardShortcut(.defaultAction).disabled(selection.path == nil)
            }.padding(Theme.inset)
        }.frame(width: 620, height: 430)
        .task { focused = true }
        .task(id: SearchIdentity(root: model.repository?.root.path, query: query)) { await filter() }
        .onDisappear { model.focusSource() }
    }

    private var footer: String {
        if isSearching { return "Searching…" }
        if totalCount > results.count { return "Showing \(results.count) of \(totalCount) matches · Type more to refine" }
        return "\(totalCount) \(totalCount == 1 ? "match" : "matches")"
    }

    private func directory(for file: RepositoryFile) -> String {
        let directory = (file.path as NSString).deletingLastPathComponent
        return directory == "." || directory.isEmpty ? file.path : directory
    }

    private func filter() async {
        let root = model.repository?.root.path
        let files = model.repository?.files ?? []
        isSearching = true
        let response = await Task.detached(priority: .userInitiated) {
            await QuickFileSearch.search(query, in: files)
        }.value
        guard !Task.isCancelled, root == model.repository?.root.path else { return }
        results = response.files
        totalCount = response.totalCount
        selection.reset(for: results)
        isSearching = false
    }

    private func moveSelection(_ delta: Int) {
        selection.move(delta, in: results)
    }

    private func openSelection() {
        guard let path = selection.path, let file = results.first(where: { $0.path == path }) else { return }
        open(file)
    }

    private func open(_ file: RepositoryFile) {
        model.openFile(file.path)
        dismiss()
    }
}

private struct SearchIdentity: Hashable {
    let root: String?
    let query: String
}
