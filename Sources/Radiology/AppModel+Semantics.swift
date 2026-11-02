import Foundation

/// Semantic navigation entry points. Destinations are resolved against the
/// file on disk before the jump, so history only ever holds exact byte offsets.
extension AppModel {
    /// Cmd-click, Return/Enter in the reader, the Navigate menu, or the
    /// context menu at a byte in the open file. Back returns to `departure`
    /// (the exact caret) when given, else to the target byte itself.
    func goToDefinition(at byte: Int, departingFrom departure: Int? = nil) {
        guard let source, let root = repository?.root else { return }
        guard let target = semantics.target(at: byte) else {
            semantics.navigationError = "No symbol is under the cursor."
            return
        }
        guard let position = target.definitions.first else {
            semantics.navigationError = target.isOnDefinition
                ? "\(target.displayName) is defined here."
                : "\(target.displayName) is defined outside this repository."
            return
        }
        semantics.navigationError = nil
        let origin = source.location(atByte: departure ?? byte)
        let generation = semanticNavigationGeneration
        Task { [semantics] in
            do {
                let destination = try await semantics.queries.resolve(position, root: root)
                guard generation == semanticNavigationGeneration, repository?.root == root else { return }
                navigateSemantically(from: origin, to: destination)
            } catch {
                guard generation == semanticNavigationGeneration else { return }
                semantics.navigationError = error.localizedDescription
            }
        }
    }

    /// Jumps to a definition chosen from a list (inspector or ⌘T).
    func navigate(toDefinition position: SemanticPosition) {
        guard let root = repository?.root else { return }
        let origin = currentCaretLocation
        let generation = semanticNavigationGeneration
        Task { [semantics] in
            do {
                let destination = try await semantics.queries.resolve(position, root: root)
                guard generation == semanticNavigationGeneration, repository?.root == root else { return }
                if let origin { navigateSemantically(from: origin, to: destination) } else { navigate(to: isReviewing ? destination.with(revision: .after) : destination) }
            } catch {
                guard generation == semanticNavigationGeneration else { return }
                semantics.navigationError = error.localizedDescription
            }
        }
    }

    /// Records the exact departure point, then the destination, so Back returns
    /// to the caret or click position rather than a stale scroll position. A
    /// pinned structural anchor stays in history; the departure is added after it.
    func navigateSemantically(from origin: SourceLocation, to destination: SourceLocation) {
        // Index data describes the After snapshot of a review, so every
        // semantic destination opens After, whatever the reader chose for
        // that path's Before/After control.
        let destination = isReviewing ? destination.with(revision: .after) : destination
        if isReviewing, let change = review?.change(touching: destination.path) { pullRequests.revisionChoices[change.id] = .after }
        navigateFromCaret(from: origin, to: destination)
    }

    /// Shared exact-caret navigation. Bookmarks keep their explicit revision;
    /// semantic callers above choose After before entering this path.
    func navigateFromCaret(from origin: SourceLocation, to destination: SourceLocation) {
        if currentHistoryEntryTracksPassivePosition {
            history.updateCurrent(origin)
            currentHistoryEntryTracksPassivePosition = false
        } else if history.current != origin {
            history.visit(origin)
        }
        navigate(to: destination)
        jumpHighlightTarget = destination
        jumpHighlightRevision += 1
    }

    /// Explicit Find References (menu, ⌃⌘R, context menu): the Context
    /// inspector lists this symbol until the reader chooses Follow Caret.
    func findReferences(at byte: Int) {
        guard let target = semantics.target(at: byte) else {
            semantics.navigationError = "No symbol is under the cursor."
            return
        }
        semantics.navigationError = nil
        context.showReferences(of: target)
    }

    func findReferencesAtCaret() {
        guard let caret = currentCaretLocation else { return }
        findReferences(at: caret.byteOffset)
    }

    func goToDefinitionAtCaret() {
        guard let caret = currentCaretLocation else { return }
        goToDefinition(at: caret.byteOffset)
    }

    /// Commits the reference row previewed in the Context inspector. Back
    /// returns to the exact caret the reader left.
    func commitSelectedReference() {
        guard let hit = context.selectedReference else { return }
        commit(hit)
    }

    /// Commits the row a native list action names (double-click or context
    /// menu), which need not be the stored keyboard selection.
    func commitReference(id: ReferenceHit.ID) {
        guard let hit = context.reference(id: id) else { return }
        commit(hit)
    }

    func commit(_ hit: ReferenceHit) {
        navigateSemantically(from: currentCaretLocation ?? hit.location, to: hit.location)
    }

    /// Activates the definition shown under the caret (button or Return).
    func goToUnderCaretDefinition() {
        guard let destination = context.underCaret?.destination else { return }
        navigate(toDefinition: destination)
    }

    /// Jumps to the enclosing declaration's name. Like every sidebar
    /// activation, the departure recorded for Back is the genuine caret,
    /// never a viewport restoration point.
    func revealDeclaration() {
        guard let declaration = context.declaration, let source, declaration.path == source.path else { return }
        let destination = source.location(atByte: declaration.declaration.selectionByteRange.lowerBound)
        navigateSemantically(from: currentCaretLocation ?? destination, to: destination)
    }

    func showSymbolSearch() {
        semantics.searchSymbols("")
        sheet = .symbols
    }

    /// Where the reader's caret is now. Never the viewport position: Back
    /// after a jump must return to the caret, not to wherever it scrolled.
    var currentCaretLocation: SourceLocation? {
        guard let source else { return nil }
        return currentCaretLocation(in: source)
    }

    func currentCaretLocation(in source: SourceBuffer) -> SourceLocation? {
        let here = source.location(atByte: 0)
        if let caretLocation, caretLocation.sameDocument(as: here) { return caretLocation }
        return navigationTarget.flatMap { $0.sameDocument(as: here) ? $0 : nil } ?? here
    }

    func reindexRepository() { semantics.reindex() }
    func cancelIndexing() { semantics.cancelIndexing() }
}
