import SwiftUI

struct ReaderCommands: Commands {
    let model: AppModel
    @FocusedBinding(\.isContextPresented) private var isContextPresented: Bool?
    var body: some Commands {
        BookmarkCommands(model: model)
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts…") { model.sheet = .keyboardHelp }
                .keyboardShortcut("/", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("Open Repository…", action: model.chooseRepository).keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentRepositories, id: \.self) { path in
                    Button(path) { model.openRepository(URL(filePath: path)) }
                }
            }.disabled(model.recentRepositories.isEmpty)
        }
        CommandGroup(after: .textEditing) {
            Button("Find in File…") { performFind(.showFindInterface) }
                .keyboardShortcut("f").disabled(model.source == nil)
            Button("Find Next") { performFind(.nextMatch) }
                .keyboardShortcut("g").disabled(model.source == nil)
            Button("Find Previous") { performFind(.previousMatch) }
                .keyboardShortcut("g", modifiers: [.command, .shift]).disabled(model.source == nil)
        }
        CommandMenu("Navigate") {
            Button("Back", action: model.goBack).keyboardShortcut("[").disabled(!model.history.canGoBack)
            Button("Forward", action: model.goForward).keyboardShortcut("]").disabled(!model.history.canGoForward)
            Divider()
            Button("Go to File…", action: model.showFiles).keyboardShortcut("k").disabled(model.repository == nil)
            Button("Go to Symbol…", action: model.showSymbolSearch).keyboardShortcut("t").disabled(model.repository == nil)
            Button("Go to Line…", action: model.showGoToLine).keyboardShortcut("l").disabled(model.source == nil)
            Button("Search Repository", action: model.showSearch).keyboardShortcut("f", modifiers: [.command, .shift]).disabled(model.repository == nil)
            Divider()
            Button("Go to Definition", action: model.goToDefinitionAtCaret)
                .keyboardShortcut("j", modifiers: [.command, .control])
                .disabled(model.semantics.caretTarget?.hasDefinition != true)
            Button("Find References", action: model.findReferencesAtCaret)
                .keyboardShortcut("r", modifiers: [.command, .control])
                .disabled(model.semantics.caretTarget == nil)
            Divider()
            Button("Next Change", action: model.goToNextChange)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!model.canGoToNextChange)
            Button("Previous Change", action: model.goToPreviousChange)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!model.canGoToPreviousChange)
        }
        CommandMenu("Pull Request") {
            Button("Open Pull Request…", action: model.showPullRequestNumber).keyboardShortcut("p")
                .disabled(!model.pullRequests.canReview)
            Button("Refresh PR", action: model.refreshCurrentPR).disabled(!model.canRefreshPR)
            Button("Refresh Pull Requests", action: model.refreshPullRequests)
                .disabled(!model.pullRequests.canReview || model.pullRequests.listPhase == .loading)
            Button("Exit PR", action: model.exitPullRequest)
                .disabled(!model.isReviewing && !model.pullRequests.isLoading)
            Divider()
            Button("Toggle Before/After", action: model.toggleRevision)
                .keyboardShortcut("b", modifiers: [.command, .option])
                .disabled(model.revisionControl.map { !$0.available.contains($0.current.other) } ?? true)
        }
        CommandMenu("Repository") {
            Button("Import Code Path…", action: model.showCodePathImport)
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!model.canImportCodePath)
            Divider()
            Button("Reindex", action: model.reindexRepository)
                .keyboardShortcut("i", modifiers: [.command, .control])
                .disabled(!model.semantics.isRepositoryOpen || model.semantics.status.isIndexing)
            Button("Cancel Indexing", action: model.cancelIndexing)
                .disabled(!model.semantics.status.isIndexing)
        }
        CommandGroup(after: .toolbar) {
            Button("Show Code Paths", action: model.showCodePaths)
                .keyboardShortcut("p", modifiers: [.command, .control])
                .disabled(model.repository == nil)
            Button(isContextPresented == true ? "Hide Context Inspector" : "Show Context Inspector",
                   action: toggleContext)
                .keyboardShortcut("i", modifiers: [.command, .option])
                .disabled(isContextPresented == nil)
            Menu("Context Panes") { InspectorPaneMenuContent(model: model) }
                .disabled(isContextPresented == nil)
            Divider()
            Button("Normal Source") { model.sourceMode = .normal }
                .keyboardShortcut("1", modifiers: [.command, .option]).disabled(model.source == nil)
            Button("Critical Lens") { model.sourceMode = .critical }
                .keyboardShortcut("2", modifiers: [.command, .option]).disabled(model.source == nil)
            Divider()
            Toggle("Source Files Only", isOn: Bindable(model).sourceFilters.sourceFilesOnly)
                .keyboardShortcut("o", modifiers: [.command, .control])
            Toggle("Hide Tests", isOn: Bindable(model).sourceFilters.hidesTests)
                .keyboardShortcut("t", modifiers: [.command, .control])
            Button("Show All Files", action: model.clearSourceFilters)
                .disabled(!model.sourceFilters.isActive)
            Divider()
            Button(model.isReviewing ? "Refresh PR" : "Reload Repository", action: model.refresh)
                .keyboardShortcut("r").disabled(model.repository == nil || model.pullRequests.isLoading)
            Button("Fold to Definitions", action: model.foldToDefinitions)
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(model.syntax == nil)
            Button("Collapse Functions", action: model.collapseFunctions)
                .keyboardShortcut("0", modifiers: [.command, .shift])
                .disabled(!model.canCollapseFunctions)
            Divider()
            Button("Increase Source Text Size", action: model.increaseFontSize).keyboardShortcut("+")
            Button("Decrease Source Text Size", action: model.decreaseFontSize).keyboardShortcut("-")
        }
    }
    private func toggleContext() { isContextPresented?.toggle() }

    private func performFind(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
    }
}
