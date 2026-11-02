import Foundation

/// Source-mode and criticality entry points. The mode is a lens over the
/// same text: switching it never navigates, records history, moves the
/// caret, or changes folds.
extension AppModel {
    var sourceMode: SourceMode {
        get { criticalLens.mode }
        set {
            guard criticalLens.mode != newValue else { return }
            criticalLens.mode = newValue
            refreshContext()
        }
    }

    /// Menu state for the SCIP symbol at a byte, or nil when nothing is
    /// there or the symbol is a document-scoped local.
    func criticalityMenu(at byte: Int) -> ReaderTextView.CriticalityMenu? {
        guard let target = semantics.target(at: byte), CriticalityOverrides.isOverridable(symbol: target.symbol.symbol) else { return nil }
        let index = semantics.index
        let header = SCIPSymbolHeader(target.symbol.symbol)
        return ReaderTextView.CriticalityMenu(displayName: target.displayName, symbol: target.symbol.symbol,
                                              packageName: header?.packageName, packageKey: header?.packageKey,
                                              builtIn: criticalLens.builtInClassification(of: target.symbol, in: index),
                                              symbolDecision: criticalLens.overrides.symbolDecision(target.symbol.symbol),
                                              packageDecision: header?.packageKey.flatMap(criticalLens.overrides.packageDecision))
    }

    // MARK: - Hover

    /// The pointer rests over a byte of the source (nil when it left the
    /// text). Only Critical mode asks; nothing here navigates or moves the
    /// caret.
    func pointerOverSource(at byte: Int?) {
        criticalSummaries.pointerMoved(to: byte.flatMap { semantics.target(at: $0) }, index: semantics.index)
    }

    func hoverPopoverHovered(_ inside: Bool) { criticalSummaries.popoverHovered(inside) }
    func dismissHoverSummary() { criticalSummaries.cancelHover() }

    /// Hover links use the existing exact-caret definition navigation path.
    func activateCriticalDestination(_ definition: SemanticPosition?, name: String) {
        guard let definition else {
            semantics.navigationError = "\(name) is defined outside this repository."
            return
        }
        semantics.navigationError = nil
        navigate(toDefinition: definition)
    }

    var canCommitSelectedRow: Bool {
        guard let id = context.selectedReferenceID else { return false }
        return context.reference(id: id) != nil
    }
}
