import Foundation
import Observation

/// Main-actor state for the caret-driven Context inspector. Two regions update
/// independently, each keyed on a stable identity rather than the caret byte:
///
/// - the enclosing Tree-sitter declaration and the SCIP references of the
///   symbol defined (or implemented) at its name;
/// - the SCIP occurrence under the caret, with metadata available at once and
///   a bounded definition preview loaded off the main actor.
///
/// Nothing here navigates, scrolls, or touches history. Disk work runs on
/// dedicated query actors so a long reference scan never delays a preview;
/// every async result is checked against the identity that requested it.
@Observable @MainActor
final class ContextModel {
    let implementations = TraitImplementationsModel()
    enum DeclarationAbsence: Sendable, Equatable {
        /// No source, or the caret is outside every declaration.
        case noDeclaration
        /// Structure has not arrived (or the language has no grammar).
        case noStructure
    }

    enum ReferencePhase: Sendable, Equatable {
        /// The declaration has no SCIP symbol; the view explains why from
        /// the index status.
        case unavailable
        case loading
        case loaded(ReferenceResults)
        case failed(String)
    }

    enum PreviewPhase: Sendable, Equatable {
        /// Nothing to preview: on the definition, a local, or no destination.
        case none
        case loading
        case loaded(DefinitionPreview)
        case unavailable(String)
    }

    /// The symbol whose references are listed when they were explicitly
    /// requested (Find References) rather than following the caret.
    struct ExplicitReferences: Sendable, Equatable {
        let symbol: SemanticSymbolID
        let displayName: String
        let kind: SemanticSymbolKind
    }

    private(set) var declaration: DeclarationContext?
    private(set) var declarationAbsence: DeclarationAbsence = .noDeclaration
    private(set) var explicitReferences: ExplicitReferences?
    private(set) var references: ReferencePhase = .unavailable
    /// The reference row being previewed in the sidebar. Selecting a row
    /// never moves the source; only `AppModel.commitSelectedReference` does.
    var selectedReferenceID: ReferenceHit.ID?
    private(set) var underCaret: UnderCaretContext?
    private(set) var preview: PreviewPhase = .none

    /// Disclosure state. The inspector is one line per item by default; each
    /// expansion belongs to an identity and collapses when it changes, while
    /// caret movement within the identity keeps it. Expanding never navigates.
    var isDeclarationExpanded = false
    var isDefinitionExpanded = false
    private(set) var expandedReferenceIDs: Set<ReferenceHit.ID> = []
    private(set) var referenceCallTrees: [ReferenceHit.ID: ReferenceCallTree.Phase] = [:]

    /// Work counters, so tests can prove that caret movement inside one token
    /// or declaration neither rebuilds context nor repeats disk queries.
    @ObservationIgnored private(set) var declarationBuildCount = 0
    @ObservationIgnored private(set) var underCaretBuildCount = 0
    @ObservationIgnored private(set) var referenceQueryCount = 0
    @ObservationIgnored private(set) var previewQueryCount = 0

    @ObservationIgnored private let referenceWorker: SemanticQueryWorker
    @ObservationIgnored private let previewWorker: SemanticQueryWorker
    @ObservationIgnored private let callerWorker = ReferenceCallTreeWorker()
    @ObservationIgnored private var callerTasks: [ReferenceHit.ID: Task<Void, Never>] = [:]
    @ObservationIgnored private var referencesTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var referencesGeneration = UUID()
    @ObservationIgnored private var previewGeneration = UUID()
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var index: SemanticIndex = .empty
    @ObservationIgnored private var indexRevision = -1
    @ObservationIgnored private var referenceCache = BoundedCache<SemanticSymbolID, ReferenceResults>(capacity: 24)
    @ObservationIgnored private var previewCache = BoundedCache<SemanticPosition, DefinitionPreview>(capacity: 64)
    /// The content identity last seen for each opened path. Cached
    /// references and previews embed source text, so new bytes at a path
    /// (a reload, or the file changed on disk) invalidate them even when the
    /// index itself was not replaced.
    @ObservationIgnored private var sourceIdentities: [String: SourceContentIdentity] = [:]

    init(referenceWorker: SemanticQueryWorker = SemanticQueryWorker(),
         previewWorker: SemanticQueryWorker = SemanticQueryWorker()) {
        self.referenceWorker = referenceWorker
        self.previewWorker = previewWorker
    }

    var selectedReference: ReferenceHit? {
        selectedReferenceID.flatMap(reference(id:))
    }

    func isReferenceExpanded(_ id: ReferenceHit.ID) -> Bool { expandedReferenceIDs.contains(id) }

    func setReference(_ id: ReferenceHit.ID, expanded: Bool) {
        guard reference(id: id) != nil, expanded != expandedReferenceIDs.contains(id) else { return }
        if expanded {
            expandedReferenceIDs.insert(id)
            if referenceCallTrees[id] == nil { loadCallTree(id: id) }
        } else {
            expandedReferenceIDs.remove(id)
            callerTasks.removeValue(forKey: id)?.cancel()
            if referenceCallTrees[id] == .loading { referenceCallTrees.removeValue(forKey: id) }
        }
    }

    func toggleReference(_ id: ReferenceHit.ID) {
        setReference(id, expanded: !isReferenceExpanded(id))
    }

    func reference(id: ReferenceHit.ID) -> ReferenceHit? {
        guard case .loaded(let results) = references else { return nil }
        return results.hit(id: id)
    }

    func traceMoreCallers(id: ReferenceHit.ID) {
        guard case .loaded(let tree) = referenceCallTrees[id], tree.hasMore else { return }
        loadCallTree(id: id, budget: tree.budget + 256)
    }

    private func loadCallTree(id: ReferenceHit.ID, budget: Int = 256) {
        guard isReferenceExpanded(id), let hit = reference(id: id), let root else { return }
        callerTasks[id]?.cancel()
        referenceCallTrees[id] = .loading
        let index = index
        let generation = referencesGeneration
        callerTasks[id] = Task { [callerWorker] in
            do {
                let tree = try await callerWorker.trace(hit, index: index, root: root, budget: budget)
                guard !Task.isCancelled, generation == referencesGeneration, isReferenceExpanded(id) else { return }
                referenceCallTrees[id] = .loaded(tree)
                callerTasks.removeValue(forKey: id)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, generation == referencesGeneration, isReferenceExpanded(id) else { return }
                referenceCallTrees[id] = .failed(error.localizedDescription)
                callerTasks.removeValue(forKey: id)
            }
        }
    }

    private func clearCallTrees() {
        for task in callerTasks.values { task.cancel() }
        callerTasks.removeAll()
        referenceCallTrees.removeAll()
    }

    // MARK: - Updates

    /// Recomputes both identities. Cheap when neither changed: one pass over
    /// the file's declarations and a binary search of its occurrences, with
    /// no observable writes.
    func update(_ inputs: ContextInputs) {
        if inputs.root != root {
            reset()
            root = inputs.root
        }
        if inputs.indexRevision != indexRevision {
            // A different index object: cached results describe the old one.
            indexRevision = inputs.indexRevision
            index = inputs.index
            referenceCache.removeAll()
            previewCache.removeAll()
            clearCallTrees()
            if let explicitReferences { loadReferences(of: explicitReferences.symbol) }
        }
        if let buffer = inputs.buffer, let identity = inputs.sourceIdentity,
           sourceIdentities.updateValue(identity, forKey: buffer.path).map({ $0 != identity }) == true {
            referenceCache.removeAll()
            previewCache.removeAll()
            clearCallTrees()
            if let explicitReferences { loadReferences(of: explicitReferences.symbol) }
        }
        updateDeclaration(inputs)
        updateUnderCaret(inputs)
        implementations.update(inputs)
        for id in expandedReferenceIDs where referenceCallTrees[id] == nil {
            loadCallTree(id: id)
        }
    }

    /// Clears everything for a new repository (or none).
    func reset() {
        implementations.reset()
        referencesTask?.cancel()
        previewTask?.cancel()
        clearCallTrees()
        referencesGeneration = UUID()
        previewGeneration = UUID()
        root = nil
        index = .empty
        indexRevision = -1
        referenceCache.removeAll()
        previewCache.removeAll()
        sourceIdentities.removeAll()
        if declaration != nil { declaration = nil }
        declarationAbsence = .noDeclaration
        if explicitReferences != nil { explicitReferences = nil }
        if references != .unavailable { references = .unavailable }
        if selectedReferenceID != nil { selectedReferenceID = nil }
        if underCaret != nil { underCaret = nil }
        if preview != .none { preview = .none }
        if isDeclarationExpanded { isDeclarationExpanded = false }
        if isDefinitionExpanded { isDefinitionExpanded = false }
        if !expandedReferenceIDs.isEmpty { expandedReferenceIDs = [] }
    }

    /// Lists a symbol's references until `followCaret()`; the declaration
    /// region keeps tracking the caret underneath.
    func showReferences(of target: SemanticTarget) {
        explicitReferences = ExplicitReferences(symbol: target.symbol, displayName: target.displayName, kind: target.kind)
        loadReferences(of: target.symbol)
    }

    func followCaret() {
        guard explicitReferences != nil else { return }
        explicitReferences = nil
        loadReferences(of: declaration?.link.symbol)
    }

    // MARK: - Declaration region

    private func updateDeclaration(_ inputs: ContextInputs) {
        guard let buffer = inputs.buffer, let identitySource = inputs.sourceIdentity,
              let syntax = inputs.syntax, syntax.path == buffer.path else {
            setDeclaration(nil, absence: inputs.buffer == nil ? .noDeclaration : .noStructure)
            return
        }
        guard let caret = inputs.caretByte,
              let symbol = DeclarationContext.innermostDeclaration(at: caret, in: syntax.symbols) else {
            setDeclaration(nil, absence: .noDeclaration)
            return
        }
        let semantics = inputs.documentSemantics?.path == buffer.path ? inputs.documentSemantics : nil
        let link = DeclarationContext.link(for: symbol, in: semantics)
        let identity = DeclarationContext.identity(path: buffer.path, declaration: symbol, source: identitySource,
                                                   link: link, indexRevision: inputs.indexRevision)
        guard identity != declaration?.identity else { return }
        declarationBuildCount += 1
        setDeclaration(DeclarationContext.make(identity: identity, declaration: symbol, link: link, buffer: buffer,
                                               folds: syntax.folds, index: inputs.index),
                       absence: .noDeclaration)
    }

    private func setDeclaration(_ context: DeclarationContext?, absence: DeclarationAbsence) {
        if declarationAbsence != absence { declarationAbsence = absence }
        guard context != declaration else { return }
        let previous = declaration?.identity
        declaration = context
        if isDeclarationExpanded { isDeclarationExpanded = false }
        guard explicitReferences == nil else { return }
        // Another declaration record for the same symbol, index, and bytes
        // keeps its loaded references and selection. New bytes reload: the
        // listed snippets came from the old contents.
        if let previous, let identity = context?.identity, identity.symbol != nil, identity.symbol == previous.symbol,
           identity.indexRevision == previous.indexRevision, identity.source == previous.source,
           references != .unavailable { return }
        loadReferences(of: context?.link.symbol)
    }

    private func loadReferences(of symbol: SemanticSymbolID?) {
        referencesTask?.cancel()
        clearCallTrees()
        referencesGeneration = UUID()
        selectedReferenceID = nil
        if !expandedReferenceIDs.isEmpty { expandedReferenceIDs = [] }
        guard let symbol, let root else {
            references = .unavailable
            return
        }
        if let cached = referenceCache[symbol] {
            references = .loaded(cached)
            return
        }
        references = .loading
        referenceQueryCount += 1
        let generation = referencesGeneration
        let index = index
        referencesTask = Task { [referenceWorker] in
            do {
                let results = try await referenceWorker.references(of: symbol, in: index, root: root)
                guard generation == referencesGeneration, !Task.isCancelled else { return }
                referenceCache[symbol] = results
                references = .loaded(results)
            } catch is CancellationError {
                return
            } catch {
                guard generation == referencesGeneration, !Task.isCancelled else { return }
                references = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Under-caret region

    private func updateUnderCaret(_ inputs: ContextInputs) {
        guard let buffer = inputs.buffer, let caret = inputs.caretByte,
              let semantics = inputs.documentSemantics, semantics.path == buffer.path,
              let target = UnderCaretContext.target(at: caret, in: semantics, index: inputs.index) else {
            setUnderCaret(nil, inputs: inputs)
            return
        }
        let identity = UnderCaretContext.identity(for: target, path: buffer.path, source: inputs.sourceIdentity,
                                                  indexRevision: inputs.indexRevision,
                                                  documentRevision: inputs.documentRevision)
        guard identity != underCaret?.identity else { return }
        underCaretBuildCount += 1
        setUnderCaret(UnderCaretContext.make(identity: identity, target: target, semantics: semantics, index: inputs.index,
                                             buffer: buffer),
                      inputs: inputs)
    }

    private func setUnderCaret(_ context: UnderCaretContext?, inputs: ContextInputs) {
        guard context?.identity != underCaret?.identity else { return }
        underCaret = context
        if isDefinitionExpanded { isDefinitionExpanded = false }
        previewTask?.cancel()
        previewGeneration = UUID()
        guard let context, context.isProminent, let destination = context.destination else {
            preview = context.map(Self.absentPreview) ?? .none
            return
        }
        if let cached = previewCache[destination] {
            preview = .loaded(cached)
            return
        }
        // A destination in the open file is read from the buffer already in
        // memory, bounded by its Tree-sitter declaration when one starts there.
        if let buffer = inputs.buffer, destination.path == buffer.path {
            guard let range = buffer.byteRange(for: destination.range, encoding: destination.encoding) else {
                preview = .unavailable("The index no longer matches this file. Reindex to refresh its preview.")
                return
            }
            let declarationEnd = inputs.syntax?.path == buffer.path
                ? DefinitionPreview.declarationEnd(at: range.lowerBound, in: inputs.syntax)
                : nil
            let result = DefinitionPreview.make(buffer: buffer, startByte: range.lowerBound,
                                                declarationEnd: declarationEnd, maxLines: DefinitionPreview.maxLines)
            previewCache[destination] = result
            preview = .loaded(result)
            return
        }
        guard let root else { preview = .none; return }
        preview = .loading
        previewQueryCount += 1
        let generation = previewGeneration
        previewTask = Task { [previewWorker] in
            do {
                let result = try await previewWorker.definitionPreview(at: destination, root: root, maxLines: DefinitionPreview.maxLines)
                guard generation == previewGeneration, !Task.isCancelled else { return }
                if let result {
                    previewCache[destination] = result
                    preview = .loaded(result)
                } else {
                    preview = .unavailable("The index no longer matches \(destination.path). Reindex to refresh its preview.")
                }
            } catch is CancellationError {
                return
            } catch {
                guard generation == previewGeneration, !Task.isCancelled else { return }
                preview = .unavailable(error.localizedDescription)
            }
        }
    }

    private static func absentPreview(_ context: UnderCaretContext) -> PreviewPhase {
        if context.isDefinedOutsideRepository {
            let source = context.externalPackage.map { "Defined in \($0), outside this repository." }
                ?? "Defined outside this repository."
            return .unavailable(source + " Its source is not indexed, so there is no preview.")
        }
        return .none
    }
}
