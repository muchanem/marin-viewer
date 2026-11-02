import SwiftUI
import Observation

@Observable @MainActor
final class AppModel {
    /// The repository being browsed: the attached folder, or the head
    /// snapshot of the pull request under review.
    var repository: RepositorySnapshot?
    /// The folder the reader opened. GitHub access, Critical Lens marks, and
    /// the working-tree index cache are keyed by it, never by a snapshot.
    private(set) var attachedRoot: URL?
    var source: SourceBuffer?
    var syntax: SyntaxSnapshot?
    var syntaxError: String?
    var isParsingSource = false
    var selectedPath: String?
    var isOpening = false
    var isLoadingSource = false
    var repositoryError: String?
    var sourceError: String?
    var searchError: String?
    var fileQuery = ""
    var filteredFiles: [RepositoryFile] = []
    var searchOptions = SearchOptions()
    var matches: [SearchMatch] = []
    var isSearching = false
    var searchLimited = false
    var mode: BrowserMode = .files
    var sheet: ReaderSheet?
    var lineInput = 1
    var pullRequestNumberInput = 1
    var currentLine = 1
    var sourceFontSize = Theme.sourceFontSize
    var navigationTarget: SourceLocation?
    var refreshedViewport: SourceLocation?
    var navigationRevision = 0
    var navigationSelectsText = true
    var foldToDefinitionsRevision = 0
    var collapseFunctionsRevision = 0
    var jumpHighlightRevision = 0
    var jumpHighlightTarget: SourceLocation?
    var focusRevision = 0
    var sourceFocusRevision = 0
    var syntacticOccurrenceSelection: SyntacticOccurrenceSelection?
    var occurrencePins = OccurrencePinStore()
    var sourceContentIdentity: SourceContentIdentity?
    var history = NavigationHistory()
    var recentRepositories: [String]
    /// Changed lines of the open document in a review; nil otherwise.
    var reviewHighlights: ReviewHighlights?
    let semantics: SemanticModel
    let context: ContextModel
    let bookmarks: BookmarkModel
    let codePaths: CodePathModel
    var inspectorRevealRevision = 0
    var sidebarRevealRevision = 0
    @ObservationIgnored let codePathResolver = CodePathResolver()
    @ObservationIgnored var codePathNavigationTask: Task<Void, Never>?
    var inspectorPanes: InspectorPanes {
        didSet {
            guard inspectorPanes != oldValue else { return }
            inspectorPanes.save(to: preferences)
        }
    }
    @ObservationIgnored let bookmarkResolver = BookmarkResolver()
    @ObservationIgnored var bookmarkNavigationTask: Task<Void, Never>?
    let criticalLens: CriticalLensModel
    let criticalSummaries: CriticalSummaryModel
    let pullRequests: PullRequestModel
    /// Hide Tests and Source Files Only, persisted app-wide. Toggling never
    /// touches the repository model, caret, history, folds, or source bytes.
    var sourceFilters: SourceFilters {
        didSet {
            guard sourceFilters != oldValue else { return }
            sourceFilters.save(to: preferences)
            // Turning Hide Tests on hides every region again.
            if sourceFilters.hidesTests, !oldValue.hidesTests, !revealedTestRegions.isEmpty { revealedTestRegions = [] }
            refreshFileTree()
        }
    }
    /// The Files tree after `sourceFilters`; the repository keeps every file.
    var fileTree: [FileNode] = []
    var visibleFileCount = 0
    /// Test regions of the loaded document the reader revealed (by start
    /// byte). Reset whenever another document loads.
    var revealedTestRegions: Set<Int> = []
    /// Expanded Files-tree directories, kept across filtering and reloads.
    let fileTreeExpansion = FileTreeExpansion()
    /// Canonical byte range of the innermost function or method around the
    /// genuine caret, shaded faintly in the source. Written only on change.
    private(set) var currentFunctionRange: Range<Int>?
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored let sessionStore: ReaderSessionStore
    @ObservationIgnored var didStartLaunch = false
    @ObservationIgnored var restoringSessionRoot: URL?
    @ObservationIgnored private let repositories = RepositoryWorker()
    @ObservationIgnored private let sources = SourceStore()
    @ObservationIgnored private let search = SearchWorker()
    @ObservationIgnored private let syntaxWorker = SyntaxWorker()
    @ObservationIgnored private var repositoryTask: Task<Void, Never>?
    @ObservationIgnored private var sourceTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var syntaxTask: Task<Void, Never>?
    @ObservationIgnored private var repositoryGeneration = UUID()
    @ObservationIgnored private var sourceGeneration = UUID()
    @ObservationIgnored private var searchGeneration = UUID()
    /// Per-document restoration points keyed by `SourceLocation.positionKey`
    /// (revision plus path). These follow the caret *and* the viewport's top
    /// line, so they are never used as the reader's caret.
    @ObservationIgnored var positions: [String: SourceLocation] = [:]
    /// The genuine caret: set only by source selection changes and by
    /// navigation that places the selection. Scrolling never moves it.
    /// Only genuine caret/navigation changes invalidate character-level affordances.
    private(set) var sourceCaretRevision = 0
    @ObservationIgnored private(set) var caretLocation: SourceLocation? {
        didSet { if caretLocation != oldValue { sourceCaretRevision += 1 } }
    }
    @ObservationIgnored var currentHistoryEntryTracksPassivePosition = false
    @ObservationIgnored var semanticNavigationGeneration = UUID()
    /// A navigation target in a document whose syntax has not arrived yet;
    /// its test region is revealed when it does.
    @ObservationIgnored private var pendingTestRevealByte: Int?

    init(preferences: UserDefaults = .standard, semantics: SemanticModel = SemanticModel(),
         context: ContextModel = ContextModel(), criticalLens: CriticalLensModel = CriticalLensModel(),
         criticalSummaries: CriticalSummaryModel = CriticalSummaryModel(),
         pullRequests: PullRequestModel = PullRequestModel()) {
        self.preferences = preferences
        sessionStore = ReaderSessionStore(preferences: preferences)
        self.semantics = semantics
        semantics.usePersonalityPreferences(preferences)
        self.context = context
        bookmarks = BookmarkModel(preferences: preferences)
        codePaths = CodePathModel(preferences: preferences)
        inspectorPanes = InspectorPanes(preferences: preferences)
        self.criticalLens = criticalLens
        self.criticalSummaries = criticalSummaries
        self.pullRequests = pullRequests
        recentRepositories = preferences.stringArray(forKey: "recentRepositories") ?? []
        sourceFilters = SourceFilters(preferences: preferences)
        semantics.onDocumentChange = { [weak self] in self?.refreshContext() }
        criticalLens.onPolicyChange = { [weak self] in self?.refreshContext() }
        pullRequests.onReviewLoaded = { [weak self] review in self?.enterReview(review) }
        pullRequests.prepareRefresh = { [weak self] old, new, snapshot, store in
            guard let self else { throw CancellationError() }
            return try await self.preparePRRefresh(old: old, new: new, snapshot: snapshot, store: store)
        }
        pullRequests.onRefreshCommitted = { [weak self] new, snapshot, restoration in
            self?.commitPRRefresh(new, snapshot: snapshot, restoration: restoration)
        }
        pullRequests.onLineChangesLoaded = { [weak self] _ in self?.refreshReviewHighlights() }
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.title = "Open Repository"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.openRepository(url)
        }
    }

    /// Opens the reader's own folder. Any pull request review ends.
    func openRepository(_ url: URL) {
        restoringSessionRoot = nil // A user's repository choice supersedes startup restoration.
        if pullRequests.review != nil || pullRequests.isLoading { pullRequests.exitReview() }
        if url.standardizedFileURL.resolvingSymlinksInPath() != attachedRoot { fileTreeExpansion.reset() }
        beginOpening(root: url, review: nil)
    }

    /// Resets every document-level state and lists `root`. With a review,
    /// `root` is the head snapshot and the attached repository identity is
    /// kept; otherwise `root` becomes the attached repository.
    func beginOpening(root url: URL, review: PullRequestReview?) {
        repositoryTask?.cancel()
        sourceTask?.cancel()
        syntaxTask?.cancel()
        cancelSearch()
        repositoryGeneration = UUID()
        let generation = repositoryGeneration
        isOpening = true
        isLoadingSource = false
        repositoryError = nil
        sourceError = nil
        searchError = nil
        source = nil
        syntax = nil
        syntacticOccurrenceSelection = nil
        occurrencePins = OccurrencePinStore()
        sourceContentIdentity = nil
        syntaxError = nil
        isParsingSource = false
        repository = nil
        selectedPath = nil
        history = NavigationHistory()
        positions = [:]
        caretLocation = nil
        matches = []
        filteredFiles = []
        fileTree = []
        visibleFileCount = 0
        if !revealedTestRegions.isEmpty { revealedTestRegions = [] }
        pendingTestRevealByte = nil
        navigationTarget = nil
        refreshedViewport = nil
        mode = review == nil ? .files : .changes
        fileQuery = ""
        sourceGeneration = UUID()
        semanticNavigationGeneration = UUID()
        if reviewHighlights != nil { reviewHighlights = nil }
        semantics.repositoryClosed()
        context.reset()
        bookmarkNavigationTask?.cancel()
        bookmarks.activate(nil)
        codePathNavigationTask?.cancel()
        codePaths.activate(nil)
        if review == nil {
            criticalLens.repositoryClosed()
            pullRequests.repositoryClosed()
        }
        criticalSummaries.reset()
        if currentFunctionRange != nil { currentFunctionRange = nil }
        repositoryTask = Task {
            do {
                let snapshot = try await repositories.open(url)
                guard generation == repositoryGeneration, !Task.isCancelled else { return }
                repository = snapshot
                refreshFileTree()
                if let review {
                    semantics.repositoryOpened(snapshot, options: review.indexOptions, selectionRoot: attachedRoot)
                    if let attachedRoot {
                        sessionStore.save(ReaderSession(repositoryPath: attachedRoot.path, pullRequest: review.number))
                    }
                } else {
                    attachedRoot = snapshot.root
                    semantics.repositoryOpened(snapshot)
                    criticalLens.repositoryOpened(snapshot.root)
                    pullRequests.repositoryOpened(root: snapshot.root, isGit: snapshot.isGit)
                    recentRepositories.removeAll { $0 == snapshot.root.path }
                    recentRepositories.insert(snapshot.root.path, at: 0)
                    recentRepositories = Array(recentRepositories.prefix(8))
                    preferences.set(recentRepositories, forKey: "recentRepositories")
                    if restoringSessionRoot == nil {
                        sessionStore.save(ReaderSession(repositoryPath: snapshot.root.path, pullRequest: nil))
                    }
                }
                if let attachedRoot {
                    bookmarks.activate(BookmarkScope(root: attachedRoot, pullRequest: review?.number))
                    codePaths.activate(attachedRoot)
                }
            } catch {
                guard generation == repositoryGeneration, !Task.isCancelled else { return }
                repositoryError = error.localizedDescription
            }
            if generation == repositoryGeneration { isOpening = false }
        }
    }

    func awaitCurrentSourceLoad() async {
        let pending = sourceTask
        await pending?.value
    }

    /// A startup waiter may use the pending task but may not reopen a PR after
    /// a newer user repository request has replaced that task/generation.
    func currentRepositoryOpening() -> (task: Task<Void, Never>?, generation: UUID) {
        (repositoryTask, repositoryGeneration)
    }

    func repositoryOpeningMatches(_ generation: UUID) -> Bool { generation == repositoryGeneration }

    /// All fallible snapshot/source preparation completed before this atomic swap.
    func commitPRRefresh(_ review: PullRequestReview, snapshot: RepositorySnapshot, restoration: PRRefreshRestoration) {
        repositoryTask?.cancel(); sourceTask?.cancel(); syntaxTask?.cancel(); cancelSearch()
        repositoryGeneration = UUID(); sourceGeneration = UUID(); semanticNavigationGeneration = UUID()
        semantics.repositoryClosed(); context.reset(); criticalSummaries.reset()
        repository = snapshot
        history = NavigationHistory(); positions = [:]
        currentHistoryEntryTracksPassivePosition = false
        matches = []; searchError = nil; repositoryError = nil; sourceError = nil; syntaxError = nil
        isOpening = false; isLoadingSource = false; isParsingSource = false
        syntax = nil; syntacticOccurrenceSelection = nil; revealedTestRegions = []; pendingTestRevealByte = nil
        if currentFunctionRange != nil { currentFunctionRange = nil }
        jumpHighlightTarget = nil; reviewHighlights = nil
        source = restoration.buffer
        sourceContentIdentity = source.map { SourceContentIdentity($0.data) }
        occurrencePins = restoration.pins
        selectedPath = source?.path
        if let buffer = source, let side = buffer.revision, let change = review.change(path: buffer.path, in: side) {
            pullRequests.revisionChoices[change.id] = side
        }
        caretLocation = restoration.caret
        navigationTarget = restoration.caret
        refreshedViewport = source.flatMap { buffer in restoration.viewportByte.map { buffer.location(atByte: $0) } }
        navigationRevision += 1
        navigationSelectsText = true
        if let caret = restoration.caret { history.visit(caret) }
        if let viewport = refreshedViewport { positions[viewport.positionKey] = viewport }
        if source == nil && restoration.notice != nil { mode = .changes }
        refreshFileTree()
        semantics.repositoryOpened(snapshot, options: review.indexOptions, selectionRoot: attachedRoot)
        if let buffer = source {
            currentLine = buffer.line(atByte: restoration.caret?.byteOffset ?? 0)
            semantics.bufferChanged(buffer.revision == .before ? nil : buffer)
            semantics.caretMoved(to: restoration.caret?.byteOffset ?? 0)
            refreshReviewHighlights(); refreshContext()
            beginParsing(buffer, generation: sourceGeneration)
        } else { currentLine = 1; refreshContext() }
    }

    /// Opens a repository and selects one file once its listing is ready.
    /// Backs the `--repository` / `--file` development launch arguments.
    func openRepository(_ url: URL, selecting path: String?) async {
        openRepository(url)
        let task = repositoryTask
        let generation = repositoryGeneration
        await task?.value
        guard let path, generation == repositoryGeneration, repository != nil else { return }
        openFile(path)
    }

    /// `--repository` with `--pull-request N`: the file, if any, opens in
    /// the review's After revision once the review has loaded.
    func openRepository(_ url: URL, selecting path: String?, pullRequest number: Int?) async {
        guard let number else { return await openRepository(url, selecting: path) }
        openRepository(url)
        let opening = currentRepositoryOpening()
        await opening.task?.value
        guard !Task.isCancelled, repositoryOpeningMatches(opening.generation), repository != nil else { return }
        let requestedRoot = attachedRoot
        openPullRequest(number)
        let deadline = ContinuousClock.now.advanced(by: .seconds(600))
        while pullRequests.isLoading, attachedRoot == requestedRoot, ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return }
        }
        guard !Task.isCancelled, attachedRoot == requestedRoot, let path, review?.number == number else { return }
        let reviewOpening = currentRepositoryOpening()
        await reviewOpening.task?.value
        guard !Task.isCancelled, repositoryOpeningMatches(reviewOpening.generation),
              attachedRoot == requestedRoot, repository != nil, review?.number == number else { return }
        navigate(to: SourceLocation(path: path, byteOffset: 0, revision: .after), tracksPassivePosition: true)
    }

    func openFile(_ path: String) {
        let location = resolveRevision(SourceLocation(path: path, byteOffset: 0))
        let restored = positions[location.positionKey]
        // A plain open at the top of the file never reveals hidden test code.
        navigate(to: restored ?? location, tracksPassivePosition: true, revealsTestCode: restored != nil)
    }

    /// `targetLine` places the caret on a one-based line of the destination
    /// once its bytes are known (revision switches map lines, not bytes).
    /// Explicit navigation into hidden test code reveals that region.
    func navigate(to requested: SourceLocation, recordHistory: Bool = true, tracksPassivePosition: Bool = false,
                  targetLine: Int? = nil, revealsTestCode: Bool = true) {
        guard let repository else { return }
        let location = resolveRevision(requested)
        refreshedViewport = nil
        if recordHistory {
            if currentHistoryEntryTracksPassivePosition,
               let source, let current = positions[source.positionKey] { history.updateCurrent(current) }
            history.visit(location)
            currentHistoryEntryTracksPassivePosition = tracksPassivePosition
        }
        navigationSelectsText = true
        selectedPath = location.path
        navigationTarget = location
        navigationRevision += 1
        caretLocation = location
        if let source, source.path == location.path, source.revision == location.revision {
            if let targetLine { place(onLine: targetLine, in: source, recordHistory: recordHistory) }
            if revealsTestCode {
                let byte = navigationTarget?.byteOffset ?? location.byteOffset
                // Structure still parsing: reveal when it arrives.
                if syntax?.path == source.path { revealTestCode(at: byte) } else { pendingTestRevealByte = byte }
            }
            currentLine = source.line(atByte: navigationTarget?.byteOffset ?? location.byteOffset)
            // The viewer places the selection inside its update pass, which
            // does not report back, so the caret's context is updated here.
            semantics.caretMoved(to: navigationTarget?.byteOffset ?? location.byteOffset)
            refreshContext()
            return
        }
        sourceTask?.cancel()
        syntaxTask?.cancel()
        sourceGeneration = UUID()
        let generation = sourceGeneration
        source = nil
        syntax = nil
        syntacticOccurrenceSelection = nil
        sourceContentIdentity = nil
        syntaxError = nil
        isParsingSource = false
        sourceError = nil
        isLoadingSource = true
        if !revealedTestRegions.isEmpty { revealedTestRegions = [] }
        pendingTestRevealByte = nil
        semantics.bufferChanged(nil)
        if reviewHighlights != nil { reviewHighlights = nil }
        refreshContext()
        sourceTask = Task {
            do {
                let root = try await sourceRoot(for: location)
                guard generation == sourceGeneration, !Task.isCancelled, repository.root == self.repository?.root else { return }
                var buffer = try await sources.load(root: root, path: location.path)
                buffer.revision = location.revision
                guard generation == sourceGeneration, !Task.isCancelled else { return }
                source = buffer
                let identity = SourceContentIdentity(buffer.data)
                sourceContentIdentity = identity
                var pins = occurrencePins
                pins.reconcile(path: buffer.positionKey, sourceIdentity: identity)
                occurrencePins = pins
                if let targetLine { place(onLine: targetLine, in: buffer, recordHistory: recordHistory) }
                let byte = navigationTarget?.byteOffset ?? location.byteOffset
                if revealsTestCode { pendingTestRevealByte = byte }
                currentLine = buffer.line(atByte: byte)
                // Before documents of a review carry no semantics: the After
                // index must never be mapped onto other bytes.
                semantics.bufferChanged(buffer.revision == .before ? nil : buffer)
                semantics.caretMoved(to: byte)
                refreshReviewHighlights()
                refreshContext()
                beginParsing(buffer, generation: generation)
            } catch {
                guard generation == sourceGeneration, !Task.isCancelled else { return }
                sourceError = error.localizedDescription
            }
            if generation == sourceGeneration { isLoadingSource = false }
        }
    }

    private func place(onLine line: Int, in buffer: SourceBuffer, recordHistory: Bool) {
        let location = buffer.location(atByte: buffer.byteOffset(line: line))
        navigationTarget = location
        navigationRevision += 1
        caretLocation = location
        if recordHistory { history.updateCurrent(location) }
    }

    private func beginParsing(_ buffer: SourceBuffer, generation: UUID) {
        guard SourceLanguageRegistry.language(for: buffer.path) != nil else { return }
        isParsingSource = true
        syntaxTask = Task {
            do {
                let result = try await syntaxWorker.parse(buffer)
                guard generation == sourceGeneration, source?.path == buffer.path, !Task.isCancelled else { return }
                syntax = result
                if let byte = pendingTestRevealByte { revealTestCode(at: byte) }
                pendingTestRevealByte = nil
                refreshContext()
            } catch is CancellationError {
                return
            } catch {
                guard generation == sourceGeneration, source?.path == buffer.path, !Task.isCancelled else { return }
                syntaxError = error.localizedDescription
            }
            if generation == sourceGeneration { isParsingSource = false }
        }
    }

    /// The source selection moved (click, arrow keys, find). Updates the
    /// caret's semantic and structural context only: it never navigates,
    /// scrolls, or records history.
    func caretMoved(to byte: Int) {
        guard let source else { return }
        let location = source.location(atByte: byte)
        guard caretLocation != location else { return }
        caretLocation = location
        semantics.caretMoved(to: byte)
        refreshContext()
    }

    func refreshContext() {
        let buffer = source
        let function = buffer.flatMap { buffer -> Range<Int>? in
            guard let syntax, syntax.path == buffer.path, let caret = currentCaretLocation(in: buffer) else { return nil }
            return syntax.innermostFunction(at: caret.byteOffset)?.byteRange
        }
        if function != currentFunctionRange { currentFunctionRange = function }
        let inputs = ContextInputs(root: repository?.root, buffer: buffer, sourceIdentity: sourceContentIdentity,
                                   syntax: syntax, caretByte: buffer.flatMap { currentCaretLocation(in: $0)?.byteOffset },
                                   index: semantics.index, indexRevision: semantics.indexRevision,
                                   documentSemantics: semantics.documentSemantics,
                                   documentRevision: semantics.documentRevision)
        context.update(inputs)
        criticalLens.update(inputs)
        criticalSummaries.update(inputs, mode: criticalLens.mode,
                                 policy: criticalLens.policy, policyRevision: criticalLens.policyRevision)
    }

    func updatePosition(path: String, byteOffset: Int, line: Int) {
        guard let source, source.path == path else { return }
        positions[source.positionKey] = source.location(atByte: byteOffset)
        currentLine = line
    }

    func preview(_ symbol: DocumentSymbol) {
        guard let source else { return }
        let location = source.location(atByte: symbol.selectionByteRange.lowerBound)
        guard navigationTarget != location else { return }
        navigationSelectsText = false
        navigationTarget = location
        navigationRevision += 1
    }

    func commit(_ symbol: DocumentSymbol, highlight: Bool = false) {
        guard let source else { return }
        let location = source.location(atByte: symbol.selectionByteRange.lowerBound)
        navigate(to: location)
        if highlight {
            jumpHighlightTarget = location
            jumpHighlightRevision += 1
        }
    }

    func foldToDefinitions() { foldToDefinitionsRevision += 1 }
    func collapseFunctions() { collapseFunctionsRevision += 1 }

    var canCollapseFunctions: Bool {
        syntax?.folds.contains { $0.kind == "function" } == true
    }

    var enclosingSymbols: [DocumentSymbol] {
        guard let source, let symbols = syntax?.symbols else { return [] }
        let byte = positions[source.positionKey]?.byteOffset ?? navigationTarget?.byteOffset ?? 0
        return symbols.filter { $0.byteRange.contains(byte) }
            .sorted { $0.byteRange.count > $1.byteRange.count }
    }

    var activeSymbol: DocumentSymbol? { enclosingSymbols.last }

    func goBack() {
        if let location = history.back() {
            currentHistoryEntryTracksPassivePosition = false
            navigate(to: location, recordHistory: false)
        }
    }
    func goForward() {
        if let location = history.forward() {
            currentHistoryEntryTracksPassivePosition = false
            navigate(to: location, recordHistory: false)
        }
    }
    func showFiles() { sheet = .files }
    func focusSource() { sourceFocusRevision += 1 }

    func selectOccurrences(at byte: Int?) {
        semantics.selectOccurrences(at: byte)
        guard let byte, let source, let syntax else {
            syntacticOccurrenceSelection = nil
            return
        }
        let syntactic = syntax.localIdentifierSelection(at: byte, in: source)
        // Prefer SCIP when it represents the complete local spelling set. If
        // cfg-gated or shadowed tokens are absent, use the explicitly
        // non-semantic function-local decoration the user requested.
        if let semantic = semantics.occurrenceSelection,
           syntactic?.byteRanges.allSatisfy(semantic.byteRanges.contains) == true {
            syntacticOccurrenceSelection = nil
        } else {
            syntacticOccurrenceSelection = syntactic
        }
    }

    func togglePinnedOccurrences(at byte: Int?) {
        guard let byte, let source, let sourceContentIdentity,
              let group = resolvedOccurrenceGroup(at: byte, source: source) else { return }
        var pins = occurrencePins
        pins.toggle(group, path: source.positionKey, sourceIdentity: sourceContentIdentity, clickedByte: byte)
        occurrencePins = pins
        // The first click in AppKit's double-click sequence may have selected
        // this transiently. A pin owns its own appearance; an unpin must leave
        // no transient wash behind.
        semantics.selectOccurrences(at: nil)
        syntacticOccurrenceSelection = nil
    }

    var pinnedOccurrenceGroups: [PinnedOccurrenceGroup] {
        guard let source, let sourceContentIdentity else { return [] }
        return occurrencePins.groups(path: source.positionKey, sourceIdentity: sourceContentIdentity)
    }

    private func resolvedOccurrenceGroup(at byte: Int, source: SourceBuffer) -> OccurrenceGroup? {
        semantics.selectOccurrences(at: byte)
        let semantic = semantics.occurrenceSelection
        let syntactic = syntax?.localIdentifierSelection(at: byte, in: source)
        if let semantic, syntactic?.byteRanges.allSatisfy(semantic.byteRanges.contains) == true {
            return OccurrenceGroup(identity: .semantic(semantic.symbol), activeByteRange: semantic.activeByteRange,
                                   byteRanges: semantic.byteRanges)
        }
        if let syntactic {
            return OccurrenceGroup(identity: .syntactic(scope: syntactic.scopeByteRange, spelling: syntactic.spelling),
                                   activeByteRange: syntactic.activeByteRange, byteRanges: syntactic.byteRanges)
        }
        if let semantic {
            return OccurrenceGroup(identity: .semantic(semantic.symbol), activeByteRange: semantic.activeByteRange,
                                   byteRanges: semantic.byteRanges)
        }
        return nil
    }
    func showSearch() { mode = .search; focusRevision += 1 }
    func showGoToLine() { lineInput = currentLine; sheet = .line }
    func goToLine() {
        guard let source else { return }
        navigate(to: source.location(atByte: source.byteOffset(line: lineInput)))
        sheet = nil
    }
    /// Reload: re-lists the browsed root (the attached folder, or the
    /// review's head snapshot) and returns to the open document.
    func refresh() {
        if isReviewing { refreshCurrentPR(); return }
        guard let root = repository?.root else { return }
        let location = source.map { positions[$0.positionKey] ?? $0.location(atByte: 0) }
        beginOpening(root: root, review: pullRequests.review)
        let task = repositoryTask
        let generation = repositoryGeneration
        Task {
            await task?.value
            if generation == repositoryGeneration, repository?.root == root, let location { navigate(to: location) }
        }
    }
    /// The Files filter field's flat list, within the same source filters.
    func filterFiles() {
        let filters = sourceFilters
        let all = (repository?.files ?? []).filter { filters.includes($0.path) }
        filteredFiles = fileQuery.isEmpty ? all : all.filter { $0.path.localizedStandardContains(fileQuery) }
    }
    /// Repository search runs over the browsed root: in a review, the After
    /// snapshot, so its hits always open After.
    func navigate(toSearchResult location: SourceLocation) {
        navigate(to: isReviewing ? location.with(revision: .after) : location)
    }
    func performSearch() {
        cancelSearch()
        matches = []
        searchError = nil
        searchLimited = false
        guard let root = repository?.root, !searchOptions.query.isEmpty else { return }
        searchGeneration = UUID()
        let generation = searchGeneration
        let options = searchOptions
        isSearching = true
        searchTask = Task { [self] in
            do {
                try await Task.sleep(for: .milliseconds(200))
                let limited = try await search.search(root: root, options: options) { [weak self] batch in
                    await self?.appendMatches(batch, generation: generation)
                }
                guard generation == searchGeneration, !Task.isCancelled else { return }
                searchLimited = limited
            } catch {
                guard generation == searchGeneration, !Task.isCancelled else { return }
                searchError = error.localizedDescription
            }
            if generation == searchGeneration { isSearching = false }
        }
    }
    private func appendMatches(_ batch: [SearchMatch], generation: UUID) {
        if generation == searchGeneration { matches.append(contentsOf: batch) }
    }
    func cancelSearch() {
        searchTask?.cancel()
        searchGeneration = UUID()
        isSearching = false
    }
    func increaseFontSize() { sourceFontSize = min(sourceFontSize + 1, 28) }
    func decreaseFontSize() { sourceFontSize = max(sourceFontSize - 1, 11) }
}
