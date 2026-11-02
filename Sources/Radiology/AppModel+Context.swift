import Foundation

/// Truthful explanations for the Context inspector's empty states, derived
/// from the index status and the open file's coverage.
extension AppModel {
    func commitCaller(_ caller: ReferenceCaller) {
        navigateSemantically(from: currentCaretLocation ?? caller.location, to: caller.location)
    }

    var semanticAvailability: SemanticAvailability {
        SemanticAvailability.resolve(status: semantics.status, index: semantics.index, path: source?.path,
                                     mappedPath: semantics.documentSemantics?.path, revision: source?.revision)
    }

    var referencesUnavailableReason: String {
        if let explanation = semanticAvailability.explanation { return explanation }
        if context.declaration?.link == DeclarationContext.Link.none {
            return "The index records no symbol for this declaration. It may be inactive in the indexed configuration (for example, a cfg-gated item), or the indexer does not name this construct."
        }
        return "No references are available."
    }

    /// One short line for the reference list when nothing can load; the full
    /// `referencesUnavailableReason` goes in its tooltip and accessibility.
    var referencesUnavailableStatus: String {
        if let header = semanticAvailability.headerDetail { return header }
        if context.declaration?.link == DeclarationContext.Link.none { return "Not in the index" }
        return "No references"
    }

    /// Shown beside "Outline" when nothing semantic is under the caret.
    var underCaretFallbackDetail: String? {
        source == nil ? nil : semanticAvailability.headerDetail
    }
}
