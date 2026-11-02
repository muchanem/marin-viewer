import Foundation
import Observation

/// Main-actor owner of source hover frontiers and fold-gutter counts.
/// Sidebar caret identities never request summaries. Work follows file,
/// index and policy revisions, or an explicit pointer dwell.
@Observable @MainActor
final class CriticalSummaryModel {
    enum Phase: Equatable, Sendable {
        case loading
        case loaded(CriticalFrontier)

        var frontier: CriticalFrontier? { if case .loaded(let frontier) = self { frontier } else { nil } }
    }

    /// What the reader shows in the hover popover for a callable occurrence.
    struct HoverPresentation: Equatable, Identifiable {
        let id: UUID
        let symbol: SemanticSymbolID
        let displayName: String
        let byteRange: Range<Int>
        let phase: Phase
        /// The hovered callable's own definition, when navigable.
        let definition: SemanticPosition?
        /// `scheme package version` when defined outside the repository.
        let externalPackage: String?
    }

    private(set) var hover: HoverPresentation?
    /// Keyed by source fold id.
    private(set) var foldAnnotations: [String: CountAnnotation] = [:]
    private(set) var isAnnotating = false

    @ObservationIgnored let worker = CallGraphWorker()
    @ObservationIgnored var hoverDwell: Duration = .milliseconds(350)
    @ObservationIgnored var hoverGrace: Duration = .milliseconds(700)
    @ObservationIgnored private var hoverInputs: ContextInputs?
    @ObservationIgnored private var configuration: CallGraphWorker.Configuration?
    @ObservationIgnored private var annotationKey: AnnotationKey?
    @ObservationIgnored private var hoverContextKey: HoverContextKey?
    @ObservationIgnored private var annotationTask: Task<Void, Never>?
    @ObservationIgnored private var hoverDwellTask: Task<Void, Never>?
    @ObservationIgnored private var hoverLoadTask: Task<Void, Never>?
    @ObservationIgnored private var hoverCloseTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var annotationGeneration = UUID()
    @ObservationIgnored private var hoverGeneration = UUID()
    @ObservationIgnored private var pendingHoverAnchor: Range<Int>?
    @ObservationIgnored private var isPointerOnAnchor = false
    @ObservationIgnored private var isPopoverHovered = false
    /// Work counters for tests.
    @ObservationIgnored private(set) var hoverRequestCount = 0
    @ObservationIgnored private(set) var annotationRunCount = 0

    private struct AnnotationKey: Equatable {
        let path: String
        let sourceIdentity: SourceContentIdentity
        let documentRevision: Int
        let indexRevision: Int
        let policyRevision: Int
    }

    private struct HoverContextKey: Equatable {
        let path: String?
        let sourceIdentity: SourceContentIdentity?
        let documentRevision: Int
        let indexRevision: Int
        let policyRevision: Int
        let mode: SourceMode
    }

    // MARK: - Updates

    func update(_ inputs: ContextInputs, mode: SourceMode,
                policy: CriticalityPolicy, policyRevision: Int) {
        guard let root = inputs.root else {
            reset()
            return
        }
        hoverInputs = inputs
        let configuration = CallGraphWorker.Configuration(root: root, index: inputs.index, indexRevision: inputs.indexRevision,
                                                          policy: policy, policyRevision: policyRevision)
        if configuration != self.configuration {
            // A different repository, index, or policy: nothing computed so far applies.
            self.configuration = configuration
            generation = UUID()
            cancelAll()
            clearAnnotations()
        }
        let hoverKey = HoverContextKey(path: inputs.buffer?.path, sourceIdentity: inputs.sourceIdentity,
                                       documentRevision: inputs.documentRevision, indexRevision: inputs.indexRevision,
                                       policyRevision: policyRevision, mode: mode)
        if hoverKey != hoverContextKey {
            hoverContextKey = hoverKey
            cancelHover()
        }
        guard mode == .critical else {
            cancelAll()
            clearAnnotations()
            annotationKey = nil
            return
        }
        updateAnnotations(inputs, configuration: configuration)
    }

    func reset() {
        configuration = nil
        hoverInputs = nil
        generation = UUID()
        cancelAll()
        clearAnnotations()
        annotationKey = nil
        hoverContextKey = nil
    }

    private func cancelAll() {
        annotationTask?.cancel()
        annotationGeneration = UUID()
        cancelHover()
    }

    private func clearAnnotations() {
        if !foldAnnotations.isEmpty { foldAnnotations = [:] }
        if isAnnotating { isAnnotating = false }
    }

    static func externalFrontier(_ symbol: SemanticSymbolID) -> CriticalFrontier {
        CriticalFrontier(summary: .noBody(.external, callable: symbol), paths: [], unknown: [],
                         coverage: .noBody(.external), traversedBodies: 0)
    }

    // MARK: - Hover

    /// The pointer rests on (or left) a semantic occurrence in the source.
    /// A callable with a repository body, or a critical external callable,
    /// opens a popover after a short dwell; leaving it closes the popover
    /// after a grace period unless the pointer has moved into the popover.
    func pointerMoved(to target: SemanticTarget?, index: SemanticIndex) {
        guard !isPopoverHovered else { return }
        guard let configuration, hoverContextKey?.mode == .critical, let target,
              target.symbol.isCallable(in: index), isHoverWorthy(target, index: index, configuration: configuration) else {
            pendingHoverAnchor = nil
            hoverDwellTask?.cancel()
            if isPointerOnAnchor {
                isPointerOnAnchor = false
                scheduleHoverClose()
            }
            return
        }
        if let hover, hover.symbol == target.symbol, hover.byteRange == target.byteRange {
            isPointerOnAnchor = true
            hoverCloseTask?.cancel()
            return
        }
        if pendingHoverAnchor == target.byteRange { return }
        pendingHoverAnchor = target.byteRange
        isPointerOnAnchor = true
        hoverDwellTask?.cancel()
        let dwell = hoverDwell
        hoverDwellTask = Task {
            try? await Task.sleep(for: dwell)
            guard !Task.isCancelled, pendingHoverAnchor == target.byteRange else { return }
            present(target, index: index, configuration: configuration)
        }
    }

    private func isHoverWorthy(_ target: SemanticTarget, index: SemanticIndex, configuration: CallGraphWorker.Configuration) -> Bool {
        if !index.definitions(of: target.symbol).isEmpty { return true }
        return configuration.policy.classify(target.symbol, in: index).criticality == .critical
    }

    private func present(_ target: SemanticTarget, index: SemanticIndex, configuration: CallGraphWorker.Configuration) {
        hoverCloseTask?.cancel()
        hoverLoadTask?.cancel()
        hoverGeneration = UUID()
        let generation = hoverGeneration
        let shared = self.generation
        let definitions = index.definitions(of: target.symbol)
        let external = definitions.isEmpty ? SCIPSymbolString.package(of: target.symbol.symbol) : nil
        let id = UUID()
        func presentation(_ phase: Phase) -> HoverPresentation {
            HoverPresentation(id: id, symbol: target.symbol, displayName: target.displayName, byteRange: target.byteRange,
                              phase: phase, definition: definitions.first, externalPackage: external)
        }
        hoverRequestCount += 1
        if definitions.isEmpty {
            hover = presentation(.loaded(Self.externalFrontier(target.symbol)))
            return
        }
        hover = presentation(.loading)
        let symbol = target.symbol
        let inputs = hoverInputs
        hoverLoadTask = Task(priority: .userInitiated) { [worker] in
            await worker.configure(configuration)
            if let buffer = inputs?.buffer {
                await worker.prime(buffer: buffer, syntax: inputs?.syntax, semantics: inputs?.documentSemantics)
            }
            let frontier = await worker.frontier(of: symbol)
            guard generation == hoverGeneration, shared == self.generation, !Task.isCancelled, hover?.id == id else { return }
            hover = presentation(.loaded(frontier))
        }
    }

    /// The pointer entered or left the popover itself.
    func popoverHovered(_ inside: Bool) {
        isPopoverHovered = inside
        if inside {
            isPointerOnAnchor = false
            pendingHoverAnchor = nil
            hoverDwellTask?.cancel()
            hoverCloseTask?.cancel()
        } else if !isPointerOnAnchor {
            scheduleHoverClose()
        }
    }

    private func scheduleHoverClose() {
        guard hover != nil || pendingHoverAnchor != nil else { return }
        hoverCloseTask?.cancel()
        let grace = hoverGrace
        hoverCloseTask = Task {
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, !isPopoverHovered, !isPointerOnAnchor else { return }
            cancelHover()
        }
    }

    /// Closes the popover at once: clicks, keys, scrolling, mode, file,
    /// index, and repository changes all come here.
    func cancelHover() {
        hoverDwellTask?.cancel()
        hoverLoadTask?.cancel()
        hoverCloseTask?.cancel()
        hoverGeneration = UUID()
        pendingHoverAnchor = nil
        isPointerOnAnchor = false
        isPopoverHovered = false
        if hover != nil { hover = nil }
    }

    // MARK: - Source gutter annotations

    private func updateAnnotations(_ inputs: ContextInputs, configuration: CallGraphWorker.Configuration) {
        guard let buffer = inputs.buffer, let identity = inputs.sourceIdentity, let syntax = inputs.syntax, syntax.path == buffer.path,
              let semantics = inputs.documentSemantics, semantics.path == buffer.path else {
            annotationKey = nil
            annotationTask?.cancel()
            if !foldAnnotations.isEmpty { foldAnnotations = [:] }
            if isAnnotating { isAnnotating = false }
            return
        }
        let key = AnnotationKey(path: buffer.path, sourceIdentity: identity, documentRevision: inputs.documentRevision,
                                indexRevision: inputs.indexRevision, policyRevision: configuration.policyRevision)
        guard key != annotationKey else { return }
        annotationKey = key
        annotationTask?.cancel()
        annotationGeneration = UUID()
        if !foldAnnotations.isEmpty { foldAnnotations = [:] }
        let callables = syntax.symbols.compactMap { symbol -> (DocumentSymbol, SourceFold)? in
            guard SyntaxSnapshot.callableKinds.contains(symbol.kind), let fold = Self.bodyFold(of: symbol, in: syntax) else { return nil }
            return (symbol, fold)
        }
        guard !callables.isEmpty else {
            if isAnnotating { isAnnotating = false }
            return
        }
        isAnnotating = true
        annotationRunCount += 1
        let generation = annotationGeneration
        let shared = self.generation
        // Lowest priority: hover must never wait on
        // this sweep, and it yields between callables.
        annotationTask = Task(priority: .utility) { [worker] in
            await worker.configure(configuration)
            var folds: [String: CountAnnotation] = [:]
            for (offset, (symbol, fold)) in callables.enumerated() {
                guard !Task.isCancelled, generation == annotationGeneration else { return }
                let link = DeclarationContext.link(for: symbol, in: semantics)
                let callable: SemanticSymbolID? = if case .defines(let id) = link { id } else { nil }
                let frontier = await worker.frontier(in: buffer, syntax: syntax, semantics: semantics, owner: symbol.byteRange,
                                                     callable: callable, hasBody: syntax.hasBody(symbol))
                guard !Task.isCancelled, generation == annotationGeneration, shared == self.generation else { return }
                let annotation = frontier.annotation
                folds[fold.id] = annotation
                if offset % 6 == 5 {
                    foldAnnotations = folds
                }
                await Task.yield()
            }
            guard generation == annotationGeneration, shared == self.generation else { return }
            foldAnnotations = folds
            isAnnotating = false
        }
    }

    /// The function fold that hides a callable's body: the outermost
    /// function fold inside the declaration after its name.
    static func bodyFold(of symbol: DocumentSymbol, in syntax: SyntaxSnapshot) -> SourceFold? {
        syntax.folds.filter {
            $0.kind == "function" && $0.byteRange.lowerBound >= symbol.selectionByteRange.upperBound
                && $0.byteRange.upperBound <= symbol.byteRange.upperBound
        }.max { $0.byteRange.count < $1.byteRange.count }
    }
}
