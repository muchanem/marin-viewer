import Foundation
import Observation

/// Main-actor state for semantic navigation: the published index, its status
/// and diagnostics, the current file's byte-mapped occurrences, the symbol
/// under the caret, reference results, and ⌘T matches. It never touches disk
/// or subprocesses itself. Reference lists live in `ContextModel`.
@Observable @MainActor
final class SemanticModel {
    var status: SemanticIndexStatus = .noIndex(reason: "Open a repository to index it.")
    var outcomes: [StrategyOutcome] = []
    var skipped: [IndexingStrategy] = []
    var unsupportedLanguages: [String] = []
    var metadata: IndexMetadata?
    var cacheDirectory: URL?
    var personality: IndexingPersonality = .default {
        didSet {
            guard personality != oldValue, let snapshot = personalitySnapshot, let selectionRoot else { return }
            personalityPreferences.save(personality, for: selectionRoot)
            repositoryOpened(snapshot, options: personalityOptions, selectionRoot: selectionRoot)
        }
    }
    var personalitySettings: IndexingPersonalitySettings?
    /// Changes whenever a different index object is published, so views drop
    /// hover and hit-test state derived from the old one.
    var indexRevision = 0
    /// Changes whenever the open file's occurrence map is replaced or cleared.
    var documentRevision = 0
    var documentSemantics: DocumentSemantics?
    var caretTarget: SemanticTarget?
    var occurrenceSelection: SemanticOccurrenceSelection?
    var symbolQuery = ""
    var symbolMatches: [SymbolSearch.Match] = []
    var isSearchingSymbols = false
    var navigationError: String?
    @ObservationIgnored private(set) var index: SemanticIndex = .empty
    @ObservationIgnored private var repositoryRoot: URL?
    @ObservationIgnored private var selectionRoot: URL?
    @ObservationIgnored private var personalitySnapshot: RepositorySnapshot?
    @ObservationIgnored private var personalityOptions = IndexOpenOptions()
    @ObservationIgnored private var personalityPreferences = IndexingPersonalityPreferences(preferences: .standard)
    @ObservationIgnored private var buffer: SourceBuffer?
    @ObservationIgnored private var caretByte = 0
    @ObservationIgnored private var documentTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var documentGeneration = UUID()
    @ObservationIgnored private var repositoryGeneration = UUID()
    @ObservationIgnored let service: SemanticIndexService
    @ObservationIgnored let queries = SemanticQueryWorker()
    /// Called after the index or the open file's occurrence map changes, so
    /// caret-derived context can re-key without polling.
    @ObservationIgnored var onDocumentChange: (() -> Void)?

    init(service: SemanticIndexService = SemanticIndexService()) {
        self.service = service
    }

    var isRepositoryOpen: Bool { repositoryRoot != nil }
    var hasIndex: Bool { index.documentCount > 0 }

    func usePersonalityPreferences(_ preferences: UserDefaults) {
        personalityPreferences = IndexingPersonalityPreferences(preferences: preferences)
    }

    // MARK: - Repository lifecycle

    func repositoryOpened(_ snapshot: RepositorySnapshot, options: IndexOpenOptions = IndexOpenOptions(), selectionRoot: URL? = nil) {
        personalitySnapshot = nil
        let selectionRoot = selectionRoot ?? snapshot.root
        self.selectionRoot = selectionRoot
        personality = personalityPreferences.load(for: selectionRoot)
        personalitySnapshot = snapshot
        personalityOptions = options
        var options = options
        options.personality = personality
        personalitySettings = nil
        documentTask?.cancel()
        searchTask?.cancel()
        repositoryGeneration = UUID()
        let generation = repositoryGeneration
        repositoryRoot = snapshot.root
        index = .empty
        indexRevision += 1
        status = .noIndex(reason: "Checking the repository…")
        outcomes = []
        skipped = []
        unsupportedLanguages = []
        metadata = nil
        cacheDirectory = nil
        documentSemantics = nil
        caretTarget = nil
        occurrenceSelection = nil
        symbolQuery = ""
        symbolMatches = []
        isSearchingSymbols = false
        navigationError = nil
        onDocumentChange?()
        let publish: SemanticIndexService.Publish = { [weak self] publication in
            await self?.receive(publication, generation: generation)
        }
        Task { [weak self, service] in
            guard self?.repositoryGeneration == generation else { return }
            await service.open(snapshot, options: options, publish: publish)
        }
    }

    func repositoryClosed() {
        repositoryGeneration = UUID()
        repositoryRoot = nil
        selectionRoot = nil
        personalitySnapshot = nil
        personalitySettings = nil
        buffer = nil
        documentTask?.cancel()
        searchTask?.cancel()
        index = .empty
        indexRevision += 1
        status = .noIndex(reason: "Open a repository to index it.")
        outcomes = []
        documentSemantics = nil
        caretTarget = nil
        occurrenceSelection = nil
        symbolMatches = []
        let generation = repositoryGeneration
        Task { [weak self, service] in
            if let self, self.repositoryGeneration != generation { return }
            await service.close()
        }
    }

    func repositoryReloaded(_ snapshot: RepositorySnapshot) {
        guard repositoryRoot == snapshot.root else { return repositoryOpened(snapshot) }
        personalitySnapshot = snapshot
        let generation = repositoryGeneration
        let publish: SemanticIndexService.Publish = { [weak self] publication in
            await self?.receive(publication, generation: generation)
        }
        Task { [service] in await service.refresh(snapshot, publish: publish) }
    }

    func reindex() {
        guard isRepositoryOpen else { return }
        Task { [service] in await service.reindex() }
    }

    func cancelIndexing() {
        Task { [service] in await service.cancel() }
    }

    func installIndexer(_ indexerID: String) {
        Task { [service] in await service.install(indexerID: indexerID) }
    }

    private func receive(_ publication: SemanticPublication, generation: UUID) {
        guard generation == repositoryGeneration, publication.repositoryRoot == repositoryRoot else { return }
        let replaced = publication.index !== index
        index = publication.index
        status = publication.status
        outcomes = publication.outcomes
        skipped = publication.skipped
        unsupportedLanguages = publication.unsupportedLanguages
        metadata = publication.metadata
        cacheDirectory = publication.cacheDirectory
        personalitySettings = publication.personalitySettings
        if replaced {
            indexRevision += 1
            caretTarget = nil
            occurrenceSelection = nil
            if let buffer { mapDocument(buffer) }
            onDocumentChange?()
        }
    }

    // MARK: - Current file

    func bufferChanged(_ buffer: SourceBuffer?) {
        self.buffer = buffer
        documentSemantics = nil
        documentRevision += 1
        caretTarget = nil
        occurrenceSelection = nil
        documentTask?.cancel()
        if let buffer { mapDocument(buffer) }
        onDocumentChange?()
    }

    private func mapDocument(_ buffer: SourceBuffer) {
        documentTask?.cancel()
        documentGeneration = UUID()
        let generation = documentGeneration
        let index = index
        guard index.documents[buffer.path] != nil else {
            if documentSemantics != nil {
                documentSemantics = nil
                documentRevision += 1
            }
            caretTarget = nil
            return
        }
        documentTask = Task { [queries] in
            let semantics = await queries.documentSemantics(index: index, buffer: buffer)
            guard generation == documentGeneration, self.buffer?.path == buffer.path, !Task.isCancelled else { return }
            documentSemantics = semantics
            documentRevision += 1
            caretTarget = target(at: caretByte)
            onDocumentChange?()
        }
    }

    /// Writes only on change: arrow keys inside one token must not
    /// invalidate views or menus observing the target.
    func caretMoved(to byte: Int) {
        caretByte = byte
        let next = target(at: byte)
        if next != caretTarget { caretTarget = next }
    }

    /// Synchronous lookup for hover, click, and menus; nil when the file has no
    /// occurrence there or no index covers it.
    func target(at byte: Int) -> SemanticTarget? {
        guard let documentSemantics, documentSemantics.path == buffer?.path else { return nil }
        return index.target(in: documentSemantics, at: byte)
    }

    /// Ordinary source clicks select every occurrence of exactly one SCIP
    /// symbol in this document. A miss clears the persistent decoration.
    func selectOccurrences(at byte: Int?) {
        guard let byte, let documentSemantics, documentSemantics.path == buffer?.path else {
            occurrenceSelection = nil
            return
        }
        occurrenceSelection = index.occurrenceSelection(in: documentSemantics, at: byte)
    }

    // MARK: - Symbol search

    func searchSymbols(_ query: String) {
        symbolQuery = query
        searchTask?.cancel()
        let index = index
        isSearchingSymbols = true
        searchTask = Task { [queries] in
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(60)) }
            guard !Task.isCancelled else { return }
            let matches = await queries.search(query, in: index)
            guard !Task.isCancelled, self.index === index, self.symbolQuery == query else { return }
            symbolMatches = matches
            isSearchingSymbols = false
        }
    }
}
