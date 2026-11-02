import Foundation
import Observation

/// A loaded pull request: pinned SHAs, the merge base, the head snapshot
/// root, the Before materialization root, and the changed files. Immutable;
/// a different head SHA is a different review.
struct PullRequestReview: Sendable, Equatable {
    let summary: PullRequestSummary
    /// GitHub's `merge_base_commit` for `baseRefOid...headRefOid`.
    let baseSHA: String
    let headSHA: String
    /// Detached worktree of `headSHA`: the After source root and index root.
    let headRoot: URL
    /// `revisions/<baseSHA>/files`: Before blobs of changed files, on demand.
    let beforeRoot: URL
    let changes: [FileChange]
    /// Blob ids of every file at `headSHA`, for exact index provenance.
    let blobIDs: [String: String]
    let indexCache: IndexCache
    let reuseSources: [IndexReuseSource]

    var number: Int { summary.number }
    var title: String { summary.title }

    func change(path: String, in revision: ReviewRevision) -> FileChange? {
        changes.first { $0.path(in: revision) == path }
    }

    /// The change touching a path in either revision (renames match both).
    func change(touching path: String) -> FileChange? {
        changes.first { $0.path == path || $0.oldPath == path }
    }

    /// Which revisions can show this path. An unchanged path exists only as
    /// the After bytes, which are also its Before bytes.
    func availableRevisions(for path: String) -> Set<ReviewRevision> {
        guard let change = change(touching: path) else { return [.after] }
        var revisions = Set<ReviewRevision>()
        if change.existsBefore { revisions.insert(.before) }
        if change.existsAfter { revisions.insert(.after) }
        return revisions
    }

    var indexOptions: IndexOpenOptions {
        IndexOpenOptions(cache: indexCache, reuseSources: reuseSources, revision: headSHA, blobIDs: blobIDs)
    }
}

/// Main-actor state for pull request review: the recent list, the loading
/// pipeline for one PR, per-path Before/After choices, and per-file line
/// changes. All gh and git work runs in `GitHubClient` and
/// `ReviewRepository`; every result is checked against the generation that
/// requested it, so a late answer for an old PR or repository is dropped.
@Observable @MainActor
final class PullRequestModel {
    enum ListPhase: Equatable, Sendable {
        case unavailable(String)
        case loading
        case loaded
        case failed(String)
    }

    private(set) var repository: GitHubRepository?
    private(set) var listPhase: ListPhase = .unavailable("Open a repository to list its pull requests.")
    private(set) var recent: [PullRequestSummary] = []
    private(set) var review: PullRequestReview?
    /// The PR being opened, with a progress message, until it loads or fails.
    private(set) var loadingNumber: Int?
    private(set) var loadingMessage: String?
    private(set) var isRefreshing = false
    private(set) var failedRefresh = false
    var refreshNotice: String?
    private(set) var failedNumber: Int?
    var loadError: String?
    /// Per changed path (After path, or the old path for a deletion).
    var revisionChoices: [String: ReviewRevision] = [:]
    private(set) var lineChanges: [String: FileLineChanges] = [:]
    private(set) var lineChangeErrors: [String: String] = [:]

    @ObservationIgnored let client: any GitHubClient
    @ObservationIgnored private let workingTreeCache: IndexCache
    @ObservationIgnored private var store: ReviewRepository?
    @ObservationIgnored private var attachedRoot: URL?
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var lineTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var activeHeadLease: UUID?
    @ObservationIgnored private let worktreeLimit: Int
    @ObservationIgnored var prepareRefresh: ((PullRequestReview, PullRequestReview, RepositorySnapshot, ReviewRepository) async throws -> PRRefreshRestoration)?
    @ObservationIgnored var onRefreshCommitted: ((PullRequestReview, RepositorySnapshot, PRRefreshRestoration) -> Void)?
    @ObservationIgnored var onReviewLoaded: ((PullRequestReview) -> Void)?
    @ObservationIgnored var onLineChangesLoaded: ((FileChange) -> Void)?

    nonisolated static let recentLimit = 25

    init(client: any GitHubClient = GHCommandClient(), workingTreeCache: IndexCache = .default, worktreeLimit: Int = ReviewRepository.worktreeLimit) {
        self.client = client
        self.workingTreeCache = workingTreeCache
        self.worktreeLimit = worktreeLimit
    }

    var isLoading: Bool { loadingNumber != nil }
    var canReview: Bool { attachedRoot != nil && store != nil }

    // MARK: - Repository lifecycle

    /// A new attached repository: every review task and all review state
    /// are dropped, then the recent list loads if this is a Git repository.
    func repositoryOpened(root: URL, isGit: Bool) {
        cancelAll()
        attachedRoot = root
        review = nil
        revisionChoices = [:]
        lineChanges = [:]
        lineChangeErrors = [:]
        loadError = nil
        failedNumber = nil
        recent = []
        repository = nil
        guard isGit else {
            store = nil
            listPhase = .unavailable("Pull requests need a Git repository with a GitHub origin.")
            return
        }
        store = try? ReviewRepository(attachedRoot: root, cacheDirectory: workingTreeCache.directory(for: root), worktreeLimit: worktreeLimit)
        guard store != nil else {
            listPhase = .unavailable("Git was not found, so pull requests cannot be fetched.")
            return
        }
        refreshList()
    }

    func repositoryClosed() {
        cancelAll()
        attachedRoot = nil
        store = nil
        review = nil
        recent = []
        repository = nil
        listPhase = .unavailable("Open a repository to list its pull requests.")
    }

    private func cancelAll() {
        releaseActiveHead()
        isRefreshing = false; failedRefresh = false; refreshNotice = nil
        listTask?.cancel()
        loadTask?.cancel()
        lineTasks.values.forEach { $0.cancel() }
        lineTasks = [:]
        generation = UUID()
        loadingNumber = nil
        loadingMessage = nil
        isRefreshing = false
    }

    // MARK: - Recent list

    func refreshList() {
        guard let attachedRoot, store != nil else { return }
        listTask?.cancel()
        let generation = generation
        listPhase = .loading
        listTask = Task { [client] in
            do {
                let repository = try await self.resolveRepository(root: attachedRoot)
                let list = try await client.listPullRequests(in: repository, limit: Self.recentLimit)
                guard generation == self.generation, !Task.isCancelled else { return }
                recent = list
                listPhase = .loaded
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                listPhase = .failed(error.localizedDescription)
            }
        }
    }

    private func resolveRepository(root: URL) async throws -> GitHubRepository {
        if let repository { return repository }
        let resolved = try await client.repository(at: root)
        guard attachedRoot == root else { throw CancellationError() }
        repository = resolved
        return resolved
    }

    // MARK: - Opening a pull request

    /// Metadata → merge base → fetch by SHA → changes → worktree → tree.
    /// Nothing here waits for indexing; the caller starts that once the
    /// review is published through `onReviewLoaded`.
    private func releaseActiveHead() {
        if let lease = activeHeadLease, let store { Task { await store.releaseHead(lease: lease) } }
        activeHeadLease = nil
    }

    func refreshCurrent() {
        guard !isLoading, let review else { return }
        start(number: review.number, refreshing: true)
    }

    func open(number: Int) { start(number: number, refreshing: false) }

    private func start(number: Int, refreshing: Bool) {
        guard let attachedRoot, let store else {
            loadError = "Pull requests are unavailable for this repository."
            return
        }
        loadTask?.cancel()
        let generation = generation
        let original = review
        isRefreshing = refreshing
        failedRefresh = false
        refreshNotice = nil
        loadingNumber = number
        loadingMessage = "Reading pull request #\(number)…"
        loadError = nil
        failedNumber = nil
        loadTask = Task { [client] in
            var candidateLease: UUID?
            defer { if let lease = candidateLease { Task { await store.releaseHead(lease: lease) } } }
            do {
                let repository = try await self.resolveRepository(root: attachedRoot)
                let summary = try await client.pullRequest(number: number, in: repository)
                guard generation == self.generation, !Task.isCancelled else { return }
                guard GHCommandClient.isSHA(summary.headRefOid), GHCommandClient.isSHA(summary.baseRefOid) else {
                    throw BrowserError.message("GitHub did not report full commit ids for #\(number).")
                }
                loadingMessage = "Finding the merge base…"
                let base = try await client.mergeBase(base: summary.baseRefOid, head: summary.headRefOid, in: repository)
                guard generation == self.generation, !Task.isCancelled else { return }
                if refreshing, let original, original.headSHA == summary.headRefOid, original.baseSHA == base {
                    review = PullRequestReview(summary: summary, baseSHA: original.baseSHA, headSHA: original.headSHA,
                        headRoot: original.headRoot, beforeRoot: original.beforeRoot, changes: original.changes,
                        blobIDs: original.blobIDs, indexCache: original.indexCache, reuseSources: original.reuseSources)
                    updateRecent(summary)
                    loadingNumber = nil; loadingMessage = nil; isRefreshing = false
                    refreshNotice = "PR is up to date."
                    return
                }
                loadingMessage = "Fetching \(summary.headRefOid.prefix(10)) and \(base.prefix(10))…"
                try await store.fetch([summary.headRefOid, base], fallbackRefs: ["refs/pull/\(number)/head", "refs/heads/\(summary.baseRefName)"])
                guard generation == self.generation, !Task.isCancelled else { return }
                loadingMessage = "Comparing \(base.prefix(10))...\(summary.headRefOid.prefix(10))…"
                let changes = try await store.changes(base: base, head: summary.headRefOid)
                guard generation == self.generation, !Task.isCancelled else { return }
                loadingMessage = "Checking out \(summary.headRefOid.prefix(10))…"
                let lease = UUID()
                candidateLease = lease
                await store.protectHead(summary.headRefOid, lease: lease)
                let headRoot = try await store.worktree(for: summary.headRefOid)
                let tree = try await store.tree(of: summary.headRefOid)
                guard generation == self.generation, !Task.isCancelled else { return }
                let blobIDs = Dictionary(tree.map { ($0.path, $0.blob) }, uniquingKeysWith: { first, _ in first })
                var reuse = [IndexReuseSource(cache: workingTreeCache, root: attachedRoot, label: "working tree")]
                for sha in await store.indexedRevisions() where sha != summary.headRefOid {
                    let cache = IndexCache(root: await store.indexDirectory(sha), flat: true)
                    reuse.append(IndexReuseSource(cache: cache, root: headRoot, label: String(sha.prefix(10))))
                }
                let loaded = PullRequestReview(summary: summary, baseSHA: base, headSHA: summary.headRefOid, headRoot: headRoot,
                                               beforeRoot: await store.filesDirectory(base), changes: changes, blobIDs: blobIDs,
                                               indexCache: IndexCache(root: await store.indexDirectory(summary.headRefOid), flat: true),
                                               reuseSources: reuse)
                guard generation == self.generation, !Task.isCancelled else { return }
                let snapshot = refreshing ? try await RepositoryWorker().open(headRoot) : nil
                let restoration: PRRefreshRestoration?
                if refreshing, let original, let snapshot, let prepareRefresh {
                    restoration = try await prepareRefresh(original, loaded, snapshot, store)
                } else { restoration = nil }
                guard generation == self.generation, !Task.isCancelled else { return }
                let oldLease = activeHeadLease
                self.generation = UUID()
                listTask?.cancel()
                if listPhase == .loading { listPhase = .loaded }
                activeHeadLease = lease
                candidateLease = nil
                lineTasks.values.forEach { $0.cancel() }
                lineTasks = [:]
                lineChanges = [:]
                lineChangeErrors = [:]
                revisionChoices = [:]
                review = loaded
                loadingNumber = nil
                loadingMessage = nil
                updateRecent(summary)
                if refreshing, let snapshot, let restoration {
                    onRefreshCommitted?(loaded, snapshot, restoration)
                    refreshNotice = restoration.notice
                } else { onReviewLoaded?(loaded) }
                isRefreshing = false
                if let oldLease { await store.releaseHead(lease: oldLease) }
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation, !Task.isCancelled else { return }
                loadingNumber = nil
                loadingMessage = nil
                isRefreshing = false
                failedRefresh = refreshing
                failedNumber = number
                loadError = error.localizedDescription
            }
        }
    }

    func retryFailedReview() {
        guard let number = failedNumber else { return }
        start(number: number, refreshing: failedRefresh)
    }

    private func updateRecent(_ summary: PullRequestSummary) {
        if let index = recent.firstIndex(where: { $0.number == summary.number }) { recent[index] = summary }
    }

    func cancelOpen() {
        loadTask?.cancel()
        loadingNumber = nil
        loadingMessage = nil
        isRefreshing = false
        loadError = nil
        failedNumber = nil
    }

    /// Leaves the review. The recent list and the GitHub repository stay.
    func exitReview() {
        releaseActiveHead()
        refreshNotice = nil
        loadTask?.cancel()
        lineTasks.values.forEach { $0.cancel() }
        lineTasks = [:]
        generation = UUID()
        review = nil
        revisionChoices = [:]
        lineChanges = [:]
        lineChangeErrors = [:]
        loadingNumber = nil
        loadingMessage = nil
        isRefreshing = false
    }

    // MARK: - Per-file data

    /// Starts loading a changed file's hunks once; results arrive through
    /// `lineChanges` and `onLineChangesLoaded`.
    func loadLineChanges(for change: FileChange) {
        guard let review, let store, lineChanges[change.id] == nil, lineTasks[change.id] == nil else { return }
        let generation = generation
        lineTasks[change.id] = Task {
            do {
                let changes = try await store.lineChanges(base: review.baseSHA, head: review.headSHA, change: change)
                guard generation == self.generation, self.review?.headSHA == review.headSHA, !Task.isCancelled else { return }
                lineChanges[change.id] = changes
                lineTasks[change.id] = nil
                onLineChangesLoaded?(change)
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation, self.review?.headSHA == review.headSHA else { return }
                lineChangeErrors[change.id] = error.localizedDescription
                lineTasks[change.id] = nil
            }
        }
    }

    /// The Before source root for a changed path, after its blob is written.
    func beforeRoot(for change: FileChange) async throws -> URL {
        guard let review, let store, change.existsBefore, let path = change.path(in: .before) else {
            throw BrowserError.message("\(change.path) does not exist before this pull request.")
        }
        return try await store.materialize(blob: change.beforeBlob, path: path, revision: review.baseSHA)
    }
}
