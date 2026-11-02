import SwiftUI

struct DocumentOutlineView: View {
    @Environment(AppModel.self) private var model
    @State private var selectedID: String?
    @State private var outline: DocumentOutline?

    var body: some View {
        let key = DocumentOutline.InputKey(path: model.source?.path, syntaxPath: model.syntax?.path,
                                          sourceIdentity: model.sourceContentIdentity, symbols: model.outlineSymbols)
        Group {
            if let syntax = model.syntax, !model.outlineSymbols.isEmpty, let outline,
               outline.path == model.source?.path, outline.sourceIdentity == model.sourceContentIdentity {
                let changed = model.changedCallableIDs
                List(selection: $selectedID) {
                    ForEach(outline.functions) { function in
                        OutlineRow(symbol: function.symbol, lineCount: function.lineCount,
                                   isChanged: changed.contains(function.id)) {
                            activate(function.symbol)
                        }
                        .tag(function.id)
                        .accessibilityValue(function.id == model.activeSymbol?.id ? "Current declaration" : "")
                    }
                    if !outline.declarations.isEmpty {
                        Section("Declarations") {
                            OutlineGroup(outline.declarations, children: \.optionalChildren) { node in
                                OutlineRow(symbol: node.symbol) { activate(node.symbol) }
                                    .tag(node.id)
                                    .accessibilityValue(node.id == model.activeSymbol?.id ? "Current declaration" : "")
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .onChange(of: selectedID) { _, id in preview(id, symbols: syntax.symbols) }
                .onChange(of: model.activeSymbol?.id) { _, id in selectedID = id }
                .onAppear { selectedID = model.activeSymbol?.id }
                .onKeyPress(.return) {
                    guard let symbol = syntax.symbols.first(where: { $0.id == selectedID }) else { return .ignored }
                    model.commit(symbol)
                    return .handled
                }
            } else if model.isParsingSource || (!model.outlineSymbols.isEmpty && outline == nil) {
                ProgressView("Reading structure…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: Theme.spacing / 2) {
                    Label("No Outline", systemImage: "list.bullet.indent")
                        .font(Theme.Fonts.meta).foregroundStyle(.primary)
                    Text(emptyDescription)
                        .font(Theme.Fonts.inspectorMetadata).foregroundStyle(.secondary)
                        .lineLimit(3).help(emptyDescription)
                }
                .padding(Theme.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Outline")
        .onChange(of: key, initial: true) { _, _ in refreshOutline() }
    }

    private func refreshOutline() {
        guard let syntax = model.syntax, let buffer = model.source, syntax.path == buffer.path else {
            outline = nil
            return
        }
        // Declarations inside hidden test code stay out of the outline.
        outline = DocumentOutline(symbols: model.outlineSymbols, buffer: buffer)
    }

    private var emptyDescription: String {
        if let syntaxError = model.syntaxError { return syntaxError }
        guard let path = model.source?.path else { return "Open a source file to see its declarations." }
        guard let language = SourceLanguageRegistry.language(for: path) else {
            return "Marin Viewer parses "
                + SourceLanguageRegistry.all.map(\.displayName).formatted(.list(type: .and))
                + ". Other files are shown as plain text."
        }
        if model.syntax?.symbols.isEmpty == false {
            return "Every declaration in this file is hidden test code. Turn off Hide Tests (⌃⌘T) to list them."
        }
        return "No declarations were found in this \(language.displayName) file."
    }

    private func preview(_ id: String?, symbols: [DocumentSymbol]) {
        guard let id, let symbol = symbols.first(where: { $0.id == id }), id != model.activeSymbol?.id else { return }
        model.preview(symbol)
    }

    private func activate(_ symbol: DocumentSymbol) {
        selectedID = symbol.id
        model.commit(symbol, highlight: true)
    }
}
