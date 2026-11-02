import SwiftUI

struct RepositorySearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(ViewerStore.self) private var viewer: ViewerStore?
    @FocusState private var searchFocused: Bool
    @State private var showOptions = false
    var body: some View {
        @Bindable var model = model
        VStack(spacing: Theme.spacing) {
            TextField("Search repository", text: $model.searchOptions.query)
                .textFieldStyle(.roundedBorder).focused($searchFocused)
                .onSubmit(model.performSearch)
            HStack {
                Toggle("Aa", isOn: $model.searchOptions.caseSensitive).help("Match case")
                Toggle(".*", isOn: $model.searchOptions.isRegex).help("Use regular expressions")
                Spacer()
                Button("Search Options", systemImage: "line.3.horizontal.decrease") { showOptions.toggle() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }.toggleStyle(.button)
            if showOptions {
                TextField("Include glob, e.g. *.swift", text: $model.searchOptions.includeGlob)
                TextField("Exclude glob, e.g. Tests/**", text: $model.searchOptions.excludeGlob)
            }
            HStack {
                Text(model.isSearching ? "Searching… \(model.matches.count) matches" : "\(model.matches.count) matches")
                    .font(Theme.Fonts.meta).foregroundStyle(.secondary)
                Spacer()
                if model.isSearching {
                    Button("Stop Search", systemImage: "stop.circle", action: model.cancelSearch).labelStyle(.iconOnly).buttonStyle(.borderless)
                }
            }
        }.padding(Theme.inset)
        .onChange(of: model.searchOptions) { model.performSearch() }
        .onChange(of: model.focusRevision) { searchFocused = true }
        .task { searchFocused = true }
        if let error = model.searchError {
            ContentUnavailableView("Search Unavailable", systemImage: "exclamationmark.magnifyingglass", description: Text(error))
        } else if model.matches.isEmpty {
            ContentUnavailableView(model.searchOptions.query.isEmpty ? "Search the Source" : model.isSearching ? "Searching" : "No Matches",
                                   systemImage: "magnifyingglass",
                                   description: Text(model.searchOptions.query.isEmpty ? "Find text across this repository." : "Try another query or adjust the options."))
        } else {
            List(model.matches) { match in
                Button {
                    // A hit in an open wordbase PR opens By file in the PR view.
                    if let viewer, viewer.isReviewing { viewer.open(path: match.path, line: match.line) }
                    else { model.navigate(toSearchResult: match.location) }
                } label: {
                    VStack(alignment: .leading, spacing: Theme.spacing / 2) {
                        Text("\(match.path):\(match.line)").font(Theme.Fonts.meta).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Text(match.preview.trimmingCharacters(in: .whitespaces))
                            .font(Theme.Fonts.codePreview).lineLimit(2).truncationMode(.tail)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                }.buttonStyle(.plain)
                .contextMenu { ViewerFileMenu(path: match.path) }
            }.listStyle(.sidebar)
            if model.searchLimited {
                Text("First 5,000 matches. Narrow your search.").font(Theme.Fonts.meta).foregroundStyle(.secondary).padding(Theme.inset)
            }
        }
    }
}
