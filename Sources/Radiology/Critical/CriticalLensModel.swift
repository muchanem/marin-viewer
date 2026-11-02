import Foundation
import Observation

/// Main-actor owner of the source mode, the repository's criticality
/// overrides, and the published `SourceProjection` for the open file. It is
/// fed the same inputs as the Context inspector and writes observable state
/// only when something the view can see has changed. All classification and
/// projection work runs on `CriticalityWorker`, guarded by a generation so a
/// slow result for an older file, index, or policy is dropped.
@Observable @MainActor
final class CriticalLensModel {
    var mode: SourceMode = .normal {
        didSet { if mode != oldValue { refresh() } }
    }
    private(set) var projection: SourceProjection?
    private(set) var overrides = CriticalityOverrides()
    private(set) var policyRevision = 0
    /// Package names that define symbols in the current index, published
    /// for synchronous menu classification; the worker keeps its own copy.
    private(set) var repositoryPackages: Set<String> = []
    /// A failed save is reported, not swallowed; the decision still applies
    /// for the session.
    private(set) var overrideError: String?

    @ObservationIgnored let worker = CriticalityWorker()
    /// Called after the policy changes (marks, or the index's repository
    /// packages arriving), so summaries that depend on it refresh.
    @ObservationIgnored var onPolicyChange: (() -> Void)?
    @ObservationIgnored private let store: CriticalityOverrideStore
    @ObservationIgnored private var root: URL?
    @ObservationIgnored private var inputs: ContextInputs?
    @ObservationIgnored private var appliedKey: ProjectionKey?
    @ObservationIgnored private var projectionTask: Task<Void, Never>?
    @ObservationIgnored private var projectionGeneration = UUID()
    @ObservationIgnored private var repositoryGeneration = UUID()
    @ObservationIgnored private var packagesIndexRevision = -1
    @ObservationIgnored private(set) var projectionRequestCount = 0
    /// Edits made before the persisted file has loaded. They apply to the
    /// session immediately and are replayed on top of the loaded set, so a
    /// slow load can never overwrite a newer decision.
    @ObservationIgnored private var pendingEdits: [(CriticalityOverrides) -> CriticalityOverrides] = []
    @ObservationIgnored private(set) var isLoadingOverrides = false
    /// Saves run strictly in order; each carries its revision so the store
    /// can also refuse an out-of-order snapshot.
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var saveRevision = 0

    private struct ProjectionKey: Equatable {
        let path: String
        let sourceIdentity: SourceContentIdentity
        let indexRevision: Int
        let documentRevision: Int
        let policyRevision: Int
        let mode: SourceMode
        let hasSyntax: Bool
    }

    init(store: CriticalityOverrideStore = CriticalityOverrideStore()) {
        self.store = store
    }

    var policy: CriticalityPolicy {
        CriticalityPolicy(repositoryPackages: repositoryPackages, overrides: overrides)
    }

    // MARK: - Repository lifecycle

    func repositoryOpened(_ root: URL) {
        repositoryGeneration = UUID()
        let generation = repositoryGeneration
        self.root = root
        if !overrides.isEmpty { overrides = CriticalityOverrides() }
        if overrideError != nil { overrideError = nil }
        policyRevision += 1
        if !repositoryPackages.isEmpty { repositoryPackages = [] }
        packagesIndexRevision = -1
        pendingEdits = []
        isLoadingOverrides = true
        clearProjection()
        Task { [store] in
            let loaded = await store.load(for: root)
            guard generation == repositoryGeneration else { return }
            isLoadingOverrides = false
            // Replay what the reader decided while the file was loading.
            let merged = pendingEdits.reduce(loaded) { $1($0) }
            let hadPending = !pendingEdits.isEmpty
            pendingEdits = []
            if merged != overrides {
                overrides = merged
                policyRevision += 1
                refresh()
                onPolicyChange?()
            }
            if hadPending { persist(merged, for: root) }
        }
    }

    func repositoryClosed() {
        repositoryGeneration = UUID()
        root = nil
        inputs = nil
        pendingEdits = []
        isLoadingOverrides = false
        if !overrides.isEmpty { overrides = CriticalityOverrides() }
        if !repositoryPackages.isEmpty { repositoryPackages = [] }
        packagesIndexRevision = -1
        clearProjection()
    }

    // MARK: - Projection

    /// Called whenever the buffer, index, document map, or caret changes.
    /// Cheap when nothing relevant changed: one key comparison.
    func update(_ inputs: ContextInputs) {
        self.inputs = inputs
        if inputs.indexRevision != packagesIndexRevision {
            packagesIndexRevision = inputs.indexRevision
            let revision = inputs.indexRevision
            let index = inputs.index
            let generation = repositoryGeneration
            Task { [worker] in
                let packages = await worker.repositoryPackages(in: index, indexRevision: revision)
                guard generation == repositoryGeneration, packagesIndexRevision == revision else { return }
                if packages != repositoryPackages {
                    repositoryPackages = packages
                    policyRevision += 1
                    refresh()
                    onPolicyChange?()
                }
            }
        }
        refresh()
    }

    private func refresh() {
        guard mode != .normal, let inputs, let buffer = inputs.buffer, let identity = inputs.sourceIdentity,
              inputs.documentSemantics == nil || inputs.documentSemantics?.path == buffer.path else {
            clearProjection()
            return
        }
        // Calls need real syntax even when the index has no document. Unknown
        // call names remain visible without inventing semantic identities.
        guard let syntax = inputs.syntax, syntax.path == buffer.path, syntax.supportsCallSites else {
            clearProjection()
            return
        }
        let semantics = inputs.documentSemantics ?? DocumentSemantics(path: buffer.path, occurrences: [], unmappedCount: 0)
        let key = ProjectionKey(path: buffer.path, sourceIdentity: identity, indexRevision: inputs.indexRevision,
                                documentRevision: inputs.documentRevision, policyRevision: policyRevision, mode: mode,
                                hasSyntax: true)
        guard key != appliedKey else { return }
        appliedKey = key
        projectionTask?.cancel()
        projectionGeneration = UUID()
        let generation = projectionGeneration
        let overrides = overrides
        let index = inputs.index
        projectionRequestCount += 1
        projectionTask = Task { [worker] in
            let result = await worker.projection(semantics: semantics, buffer: buffer, syntax: syntax, index: index,
                                                 indexRevision: key.indexRevision, documentRevision: key.documentRevision,
                                                 overrides: overrides, policyRevision: key.policyRevision)
            guard generation == projectionGeneration, !Task.isCancelled else { return }
            projection = result
        }
    }

    private func clearProjection() {
        projectionTask?.cancel()
        projectionGeneration = UUID()
        appliedKey = nil
        if projection != nil { projection = nil }
    }

    // MARK: - Classification and overrides

    func classification(of id: SemanticSymbolID, in index: SemanticIndex) -> CriticalityClassification {
        policy.classify(id, in: index)
    }

    func builtInClassification(of id: SemanticSymbolID, in index: SemanticIndex) -> CriticalityClassification {
        policy.builtInClassification(id, in: index)
    }

    /// `nil` restores the built-in policy. Locals are never stored.
    func setSymbol(_ symbol: String, to value: Criticality?) {
        guard CriticalityOverrides.isOverridable(symbol: symbol) else { return }
        apply { var updated = $0; updated.setSymbol(symbol, to: value); return updated }
    }

    func setPackage(_ package: String, to value: Criticality?) {
        apply { var updated = $0; updated.setPackage(package, to: value); return updated }
    }

    private func apply(_ edit: @escaping (CriticalityOverrides) -> CriticalityOverrides) {
        let updated = edit(overrides)
        if isLoadingOverrides { pendingEdits.append(edit) }
        guard updated != overrides else { return }
        overrides = updated
        policyRevision += 1
        refresh()
        onPolicyChange?()
        // While loading, the replay after load persists the merged result.
        guard !isLoadingOverrides, let root else { return }
        persist(updated, for: root)
    }

    private func persist(_ snapshot: CriticalityOverrides, for root: URL) {
        saveRevision += 1
        let revision = saveRevision
        let generation = repositoryGeneration
        let previous = saveTask
        saveTask = Task { [store] in
            await previous?.value
            do {
                try await store.save(snapshot, for: root, revision: revision)
                guard generation == repositoryGeneration else { return }
                if overrideError != nil { overrideError = nil }
            } catch {
                guard generation == repositoryGeneration else { return }
                overrideError = "Could not save criticality decisions: \(error.localizedDescription)"
            }
        }
    }

    /// Waits for every queued save; for tests.
    func flushSaves() async { await saveTask?.value }
}
