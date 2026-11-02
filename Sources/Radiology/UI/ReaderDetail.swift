import SwiftUI

struct ReaderDetail: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: 0) {
            if let source = model.source, let root = model.repository?.root {
                SourceBreadcrumbs(rootName: model.attachedRoot?.lastPathComponent ?? root.lastPathComponent, path: source.path,
                                  symbols: model.enclosingSymbols,
                                  canCollapseFunctions: model.canCollapseFunctions,
                                  isReviewing: model.isReviewing,
                                  canPreviousChange: model.canGoToPreviousChange,
                                  canNextChange: model.canGoToNextChange,
                                  previousChange: model.goToPreviousChange, nextChange: model.goToNextChange,
                                  collapseFunctions: model.collapseFunctions) { model.commit($0) }
                Divider()
                let highlights = model.reviewHighlights.flatMap { $0.path == source.path && $0.sourceIdentity == model.sourceContentIdentity ? $0 : nil }
                SourceViewer(buffer: source, fontSize: model.sourceFontSize, syntax: model.syntax, target: model.navigationTarget,
                             revision: model.navigationRevision, selectsTarget: model.navigationSelectsText,
                             focusRevision: model.sourceFocusRevision,
                             foldToDefinitionsRevision: model.foldToDefinitionsRevision,
                             collapseFunctionsRevision: model.collapseFunctionsRevision,
                             highlightTarget: model.jumpHighlightTarget,
                             highlightRevision: model.jumpHighlightRevision,
                             semanticRevision: model.semantics.indexRevision + model.semantics.documentRevision,
                             semanticTarget: { model.semantics.target(at: $0) },
                             occurrenceHighlightRanges: model.syntacticOccurrenceSelection?.byteRanges
                                ?? model.semantics.occurrenceSelection?.byteRanges ?? [],
                             activeOccurrenceHighlightRange: model.syntacticOccurrenceSelection?.activeByteRange
                                ?? model.semantics.occurrenceSelection?.activeByteRange,
                             functionShadeRange: model.currentFunctionRange,
                             changedByteRanges: highlights?.byteRanges ?? [],
                             changedLineRanges: highlights?.lineRanges ?? [],
                             changeRevision: highlights?.revision,
                             reviewIdentity: model.reviewFoldIdentity, reviewFoldInput: model.reviewFoldInput,
                             refreshedViewport: model.refreshedViewport,
                             projection: model.criticalLens.projection,
                             sourceIdentity: model.sourceContentIdentity,
                             testCodePresentation: model.testCodePresentation,
                             onToggleTestRegion: { model.toggleTestRegion($0) },
                             pinnedOccurrenceGroups: model.pinnedOccurrenceGroups,
                             criticalityMenu: { model.criticalityMenu(at: $0) },
                             pointerSummariesEnabled: model.sourceMode == .critical,
                             hoverPresentation: model.criticalSummaries.hover,
                             foldAnnotations: model.criticalSummaries.foldAnnotations,
                             onPointerOverSource: { model.pointerOverSource(at: $0) },
                             onHoverNavigate: { model.activateCriticalDestination($0, name: $1) },
                             onPopoverHover: { model.hoverPopoverHovered($0) },
                             onHoverDismiss: { model.dismissHoverSummary() },
                             onSetSymbolCriticality: { model.criticalLens.setSymbol($0, to: $1) },
                             onSetPackageCriticality: { model.criticalLens.setPackage($0, to: $1) },
                             onSelectOccurrences: { model.selectOccurrences(at: $0) },
                             onTogglePinnedOccurrences: { model.togglePinnedOccurrences(at: $0) },
                             onGoToDefinition: { model.goToDefinition(at: $0) },
                             onKeyboardGoToDefinition: { model.goToDefinition(at: $0, departingFrom: $1) },
                             onFindReferences: { model.findReferences(at: $0) },
                             onCaret: { model.caretMoved(to: $0) }) { byte, line in
                    model.updatePosition(path: source.path, byteOffset: byte, line: line)
                }
                Divider()
                HStack {
                    Text(RepositoryFile(path: source.path).language)
                    Text("·").accessibilityHidden(true)
                    Text("\(source.lineCount) lines")
                    TestCodeStatusView()
                    if let syntaxError = model.syntaxError {
                        Text("·").accessibilityHidden(true)
                        Label("Structure unavailable", systemImage: "exclamationmark.triangle")
                            .help(syntaxError)
                    } else if model.syntax?.hasParseErrors == true {
                        Text("·").accessibilityHidden(true)
                        Label("Partial structure", systemImage: "exclamationmark.triangle")
                            .help("This file does not fully parse, so highlighting and the outline may be incomplete.")
                    }
                    Spacer()
                    if let overrideError = model.criticalLens.overrideError {
                        Label("Marks not saved", systemImage: "exclamationmark.triangle").help(overrideError)
                        Text("·").accessibilityHidden(true)
                    }
                    SemanticStatusView()
                    Text("·").accessibilityHidden(true)
                    Button("Line \(model.currentLine)", action: model.showGoToLine).buttonStyle(.borderless).help("Go to Line (⌘L)")
                    if let revision = source.revision {
                        Text("\(revision.title) · UTF-8 · Read Only")
                    } else {
                        Text("UTF-8 · Read Only")
                    }
                }.font(Theme.Fonts.meta).foregroundStyle(.secondary).padding(Theme.inset)
            } else if model.isOpening || model.isLoadingSource {
                ProgressView(model.isOpening ? "Opening repository…" : "Reading source…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.repositoryError ?? model.sourceError {
                ContentUnavailableView("Unable to Open", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if model.repository != nil {
                ContentUnavailableView("Choose a File", systemImage: "doc.text.magnifyingglass", description: Text("Browse the sidebar or press ⌘K to find a file."))
            } else {
                WelcomeView()
            }
        }.background(Color(nsColor: .textBackgroundColor))
    }
}
