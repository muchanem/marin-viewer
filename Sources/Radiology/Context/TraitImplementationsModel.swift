import Foundation
import Observation

/// Trait context is independent of declaration/reference selection. Following
/// a trait through its members or impl body keeps list selection stable.
@Observable @MainActor
final class TraitImplementationsModel {
    private(set) var symbol: SemanticSymbolID?
    private(set) var displayName = ""
    private(set) var groups: [TraitImplementationGroup] = []
    private(set) var coverageDetail = ""
    private(set) var hasGaps = false
    private(set) var isPrepared = false
    private(set) var count = 0
    private(set) var negativeCount = 0
    var selectedID: TraitImplementation.ID?
    var navigationError: String?
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var revision = -1
    @ObservationIgnored private var source: SourceContentIdentity?
    @ObservationIgnored let worker = TraitImplementationWorker()

    func item(id: TraitImplementation.ID) -> TraitImplementation? {
        for group in groups { if let item = group.items.first(where: { $0.id == id }) { return item } }
        return nil
    }

    func update(_ inputs: ContextInputs) {
        let target = Self.trait(in: inputs)
        guard target != symbol || inputs.indexRevision != revision || inputs.root != root || inputs.sourceIdentity != source else { return }
        let retainRows = target == symbol && inputs.indexRevision == revision && inputs.root == root
        if !retainRows { clearSelection() }
        source = inputs.sourceIdentity
        root = inputs.root
        revision = inputs.indexRevision
        symbol = target
        displayName = target.map(inputs.index.displayName) ?? ""
        let catalog = inputs.index.traitImplementations
        isPrepared = catalog.isPrepared
        coverageDetail = catalog.coverageDetail
        hasGaps = catalog.hasGaps
        let rows = target.flatMap { catalog.byTrait[$0] } ?? []
        count = rows.count { !$0.isNegative }
        negativeCount = rows.count { $0.isNegative }
        groups = Dictionary(grouping: rows, by: \.path).map { path, items in
            TraitImplementationGroup(path: path, items: items.sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound })
        }.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// A trait name under the caret wins; otherwise follow the enclosing
    /// trait or trait impl, including requirements and default method bodies.
    private static func trait(in inputs: ContextInputs) -> SemanticSymbolID? {
        guard let buffer = inputs.buffer, let syntax = inputs.syntax, syntax.path == buffer.path,
              syntax.languageID == "rust", let caret = inputs.caretByte,
              let semantics = inputs.documentSemantics, semantics.path == buffer.path else { return nil }
        if let target = UnderCaretContext.target(at: caret, in: semantics, index: inputs.index),
           [42, 53].contains(target.kind.rawValue) { return target.symbol }
        if let declaration = syntax.symbols.filter({ $0.kind == "protocol" && $0.byteRange.contains(caret) })
            .min(by: { $0.byteRange.count < $1.byteRange.count }),
           case .defines(let id) = DeclarationContext.link(for: declaration, in: semantics) { return id }
        if let item = syntax.rustTraitImpls.filter({ $0.byteRange.contains(caret) })
            .min(by: { $0.byteRange.count < $1.byteRange.count }) {
            let ids = Set(semantics.occurrences(at: item.traitNameRange.lowerBound).filter {
                !$0.isDefinition && !$0.symbol.isLocal && $0.byteRange == item.traitNameRange
            }.map(\.symbol))
            if ids.count == 1 { return ids.first }
        }
        return nil
    }

    func reset() {
        clearSelection()
        root = nil
        source = nil
        revision = -1
        symbol = nil
        groups = []
        displayName = ""
        isPrepared = false
        count = 0
        negativeCount = 0
    }

    private func clearSelection() {
        selectedID = nil
        navigationError = nil
    }

}
