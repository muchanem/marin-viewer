import SwiftUI

/// ⌘T: repository symbols from the semantic index, ranked by `SymbolSearch`.
struct SymbolSearchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: SemanticSymbolID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "function").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("Go to symbol", text: $query).textFieldStyle(.plain).focused($focused).onSubmit(openSelection)
                Text("⌘T").font(Theme.Fonts.meta).foregroundStyle(.secondary)
            }.padding(Theme.inset * 1.5)
            Divider()
            if model.semantics.hasIndex {
                if model.semantics.symbolMatches.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "No Symbols" : "No Matches", systemImage: "function",
                                           description: Text(query.isEmpty ? "The index has no repository symbols." : "Try a shorter name, initials, or another spelling."))
                        .frame(maxHeight: .infinity)
                } else {
                    List(model.semantics.symbolMatches, selection: $selection) { match in
                        Button { open(match) } label: {
                            SymbolSearchRow(match: match)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .tag(match.id)
                    }.onSubmit(openSelection)
                }
            } else {
                ContentUnavailableView(emptyTitle, systemImage: emptySymbol, description: Text(emptyDescription))
                    .frame(maxHeight: .infinity)
            }
            Divider()
            HStack {
                Text(footer).font(Theme.Fonts.meta).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Go", action: openSelection).keyboardShortcut(.defaultAction).disabled(selection == nil)
            }.padding(Theme.inset)
        }.frame(width: 620, height: 430)
        .task { focused = true; selection = model.semantics.symbolMatches.first?.id }
        .onChange(of: query) { model.semantics.searchSymbols(query) }
        .onChange(of: model.semantics.symbolMatches) { selection = model.semantics.symbolMatches.first?.id }
    }

    private var footer: String {
        "\(model.semantics.symbolMatches.count) symbols · Index \(model.semantics.status.label.lowercased())"
    }

    private var emptyTitle: String {
        switch model.semantics.status {
        case .indexing: "Indexing"
        case .failed: "Index Unavailable"
        default: "No Semantic Index"
        }
    }

    private var emptySymbol: String {
        if case .failed = model.semantics.status { return "exclamationmark.triangle" }
        return "function"
    }

    private var emptyDescription: String {
        switch model.semantics.status {
        case .indexing(let progress): progress.message
        case .failed(let failure): failure.message
        case .noIndex(let reason): reason
        default: "Symbols appear once the repository is indexed."
        }
    }

    private func openSelection() {
        guard let selection, let match = model.semantics.symbolMatches.first(where: { $0.id == selection }) else { return }
        open(match)
    }

    private func open(_ match: SymbolSearch.Match) {
        model.navigate(toDefinition: match.entry.position)
        dismiss()
    }
}

struct SymbolSearchRow: View {
    let match: SymbolSearch.Match
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
            Image(systemName: match.entry.kind.systemImage).foregroundStyle(.secondary).frame(width: 16).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing / 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
                    Text(match.entry.name).font(Theme.Fonts.body)
                    Text(match.entry.kind.name).font(Theme.Fonts.meta).foregroundStyle(.secondary)
                    if match.entry.definitionCount > 1 {
                        Text("\(match.entry.definitionCount) definitions").font(Theme.Fonts.meta).foregroundStyle(.secondary)
                    }
                }
                Text("\(match.entry.position.path):\(match.entry.position.range.startLine + 1)")
                    .font(Theme.Fonts.meta).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(match.entry.name), \(match.entry.kind.name), \(match.entry.position.path) line \(match.entry.position.range.startLine + 1)")
    }
}
