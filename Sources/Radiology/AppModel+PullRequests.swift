import Foundation

/// Changed lines of the open document, converted to its exact bytes, for the
/// gutter, the line wash, outline marks, and change navigation.
struct ReviewHighlights: Equatable, Sendable {
    let path: String
    let revision: ReviewRevision
    let sourceIdentity: SourceContentIdentity
    /// One-based line ranges, sorted and disjoint.
    let lineRanges: [Range<Int>]
    /// The same ranges as canonical byte ranges covering whole lines.
    let byteRanges: [Range<Int>]
    /// First line of each change, for Next/Previous Change.
    let anchors: [Int]
    let isBinary: Bool
}

/// Pull request review entry points. The attached repository stays the
/// identity for GitHub access, Critical Lens marks, and the working-tree
/// index cache; `repository` is the head snapshot while a review is open.
extension AppModel {
    var review: PullRequestReview? { pullRequests.review }
    var isReviewing: Bool { pullRequests.review != nil }

    /// Toolbar menu selection: nil is the local checkout, a number is a PR.
    var pullRequestSelection: Int? {
        get { pullRequests.loadingNumber ?? review?.number }
        set {
            if let number = newValue {
                if number != review?.number { openPullRequest(number) }
            } else if isReviewing || pullRequests.isLoading {
                exitPullRequest()
            }
        }
    }

    func showPullRequestNumber() {
        guard pullRequests.canReview else { return }
        let remembered = sessionStore.load().flatMap { $0.repositoryURL == attachedRoot ? $0.pullRequest : nil }
        pullRequestNumberInput = review?.number ?? remembered ?? pullRequests.recent.first?.number ?? 1
        sheet = .pullRequest
    }

    func openPullRequestFromSheet() {
        sheet = nil
        openPullRequest(pullRequestNumberInput)
    }

    func openPullRequest(_ number: Int) {
        guard number > 0, pullRequests.canReview else { return }
        pullRequests.open(number: number)
    }

    func refreshPullRequests() { pullRequests.refreshList() }

    /// Local Checkout: reopens the attached folder exactly as Reload does.
    func exitPullRequest() {
        guard let attachedRoot else { return }
        restoringSessionRoot = nil
        sessionStore.save(ReaderSession(repositoryPath: attachedRoot.path, pullRequest: nil))
        pullRequests.cancelOpen()
        guard isReviewing else { return }
        pullRequests.exitReview()
        openRepository(attachedRoot)
    }

    /// Called by the pull request model once a review is loaded: the head
    /// snapshot becomes the browsed repository and its index starts.
    func enterReview(_ loaded: PullRequestReview) {
        beginOpening(root: loaded.headRoot, review: loaded)
    }

    // MARK: - Revisions

    /// Explicit revision for a location: outside a review none; inside, the
    /// requested one, else the reader's choice for that path, else After
    /// (Before only for paths that no longer exist).
    func resolveRevision(_ location: SourceLocation) -> SourceLocation {
        guard let review else { return location.revision == nil ? location : location.with(revision: nil) }
        if let revision = location.revision { return location.with(revision: revision) }
        let available = review.availableRevisions(for: location.path)
        if let change = review.change(touching: location.path), let chosen = pullRequests.revisionChoices[change.id], available.contains(chosen) {
            return location.with(revision: chosen)
        }
        return location.with(revision: available.contains(.after) ? .after : .before)
    }

    /// The directory a location's bytes are read from.
    func sourceRoot(for location: SourceLocation) async throws -> URL {
        guard let repository else { throw BrowserError.message("No repository is open.") }
        guard let review, location.revision == .before else { return repository.root }
        guard let change = review.change(path: location.path, in: .before) else {
            throw BrowserError.message("\(location.path) is unchanged in this pull request; the After bytes are also its Before bytes.")
        }
        return try await pullRequests.beforeRoot(for: change)
    }

    var currentRevision: ReviewRevision? { source?.revision }

    /// What the per-file control can offer for the open document.
    var revisionControl: ReviewRevisionControl? {
        guard let review, let source, let revision = source.revision else { return nil }
        let change = review.change(path: source.path, in: revision)
        let available = change.map { change -> Set<ReviewRevision> in
            var set = Set<ReviewRevision>()
            if change.existsBefore { set.insert(.before) }
            if change.existsAfter { set.insert(.after) }
            return set
        } ?? [.after]
        let status: String
        if let change {
            switch change.status {
            case .renamed, .copied: status = revision == .after ? "\(change.status.title) from \(change.oldPath ?? "")" : "\(change.status.title) to \(change.path)"
            default: status = change.isBinary ? "Binary" : change.status.title
            }
        } else {
            status = "Unchanged"
        }
        return ReviewRevisionControl(current: revision, available: available, status: status, isBinary: change?.isBinary == true)
    }

    /// Switches the open document to the other revision at the corresponding
    /// line. Recorded in history, so ⌘[ returns to the exact caret here.
    func toggleRevision() {
        guard let control = revisionControl, control.available.contains(control.current.other) else { return }
        setRevision(control.current.other)
    }

    func setRevision(_ revision: ReviewRevision) {
        guard let review, let source, let current = source.revision, current != revision,
              let change = review.change(path: source.path, in: current),
              let path = change.path(in: revision) else { return }
        pullRequests.revisionChoices[change.id] = revision
        let caret = currentCaretLocation(in: source) ?? source.location(atByte: 0)
        let line = source.line(atByte: caret.byteOffset)
        let mapped = pullRequests.lineChanges[change.id].map { LineMap($0).map(line: line, from: current) } ?? line
        // Like a semantic jump, the departure recorded for Back is the
        // genuine caret, not a viewport restoration point.
        if currentHistoryEntryTracksPassivePosition {
            history.updateCurrent(caret)
            currentHistoryEntryTracksPassivePosition = false
        } else if history.current != caret {
            history.visit(caret)
        }
        navigate(to: SourceLocation(path: path, byteOffset: 0, revision: revision), targetLine: mapped)
    }

    /// Opens a changed file from the Changes list in its natural revision.
    func openChange(_ change: FileChange) {
        guard let review, review.changes.contains(change) else { return }
        if change.existsAfter {
            let revision = pullRequests.revisionChoices[change.id] ?? .after
            let path = change.path(in: revision) ?? change.path
            let location = SourceLocation(path: path, byteOffset: 0, revision: revision)
            navigate(to: positions[location.positionKey] ?? location, tracksPassivePosition: true)
        } else {
            let location = SourceLocation(path: change.oldPath ?? change.path, byteOffset: 0, revision: .before)
            navigate(to: positions[location.positionKey] ?? location, tracksPassivePosition: true)
        }
    }

    // MARK: - Highlights

    /// Recomputed when the document, its revision, or its line changes change.
    func refreshReviewHighlights() {
        guard let review, let source, let revision = source.revision, let identity = sourceContentIdentity,
              let change = review.change(path: source.path, in: revision) else {
            if reviewHighlights != nil { reviewHighlights = nil }
            return
        }
        guard let changes = pullRequests.lineChanges[change.id] else {
            pullRequests.loadLineChanges(for: change)
            if reviewHighlights != nil { reviewHighlights = nil }
            return
        }
        let lineRanges = changes.changedLines(in: revision).filter { $0.lowerBound <= source.lineCount }
            .map { $0.lowerBound..<min($0.upperBound, source.lineCount + 1) }
        let byteRanges = lineRanges.map { range -> Range<Int> in
            let start = source.lineStarts[range.lowerBound - 1]
            let end = range.upperBound - 1 < source.lineCount ? source.lineStarts[range.upperBound - 1] : source.data.count
            return start..<end
        }
        let next = ReviewHighlights(path: source.path, revision: revision, sourceIdentity: identity, lineRanges: lineRanges,
                                    byteRanges: byteRanges, anchors: changes.changeAnchors(in: revision).map { min(max(1, $0), source.lineCount) },
                                    isBinary: changes.isBinary)
        if next != reviewHighlights { reviewHighlights = next }
    }

    /// Outline rows for callables whose span contains a changed line.
    var changedCallableIDs: Set<String> {
        guard let highlights = reviewHighlights, let syntax, syntax.path == highlights.path,
              highlights.sourceIdentity == sourceContentIdentity else { return [] }
        var ids = Set<String>()
        for symbol in syntax.symbols where SyntaxSnapshot.callableKinds.contains(symbol.kind) {
            if highlights.byteRanges.contains(where: { $0.overlaps(symbol.byteRange) }) { ids.insert(symbol.id) }
        }
        return ids
    }

    var reviewFoldIdentity: String? { review.map { "\($0.number):\($0.baseSHA):\($0.headSHA)" } }

    var reviewFoldInput: ReviewFoldInput? {
        guard let reviewID = reviewFoldIdentity, let source, let revision = source.revision,
              let identity = sourceContentIdentity, let highlights = reviewHighlights,
              highlights.path == source.path, highlights.revision == revision, highlights.sourceIdentity == identity,
              let change = review?.change(path: source.path, in: revision),
              let changes = pullRequests.lineChanges[change.id] else { return nil }
        return ReviewFoldInput(reviewID: reviewID, path: source.path, revision: revision, sourceIdentity: identity, changes: changes)
    }

    var changeBlockNavigation: ChangeBlockNavigation? {
        _ = sourceCaretRevision
        guard let source, let revision = source.revision, let highlights = reviewHighlights,
              highlights.path == source.path, highlights.revision == revision,
              highlights.sourceIdentity == sourceContentIdentity, !highlights.isBinary,
              let change = review?.change(path: source.path, in: revision),
              let changes = pullRequests.lineChanges[change.id] else { return nil }
        return ChangeBlockNavigation(changes: changes, buffer: source,
                                     caret: currentCaretLocation(in: source)?.byteOffset ?? 0)
    }

    var canGoToNextChange: Bool { changeBlockNavigation?.nextByte != nil }
    var canGoToPreviousChange: Bool { changeBlockNavigation?.previousByte != nil }
    func goToNextChange() { goToChange(forward: true) }
    func goToPreviousChange() { goToChange(forward: false) }

    private func goToChange(forward: Bool) {
        guard let source, let blocks = changeBlockNavigation,
              let byte = forward ? blocks.nextByte : blocks.previousByte else { return }
        let departure = currentCaretLocation(in: source) ?? source.location(atByte: 0)
        if currentHistoryEntryTracksPassivePosition {
            history.updateCurrent(departure)
            currentHistoryEntryTracksPassivePosition = false
        } else if history.current != departure {
            history.visit(departure)
        }
        navigate(to: source.location(atByte: byte))
        jumpHighlightTarget = navigationTarget
        jumpHighlightRevision += 1
        focusSource()
    }

}

/// What the Before/After control shows for the open document.
struct ReviewRevisionControl: Equatable, Sendable {
    let current: ReviewRevision
    let available: Set<ReviewRevision>
    let status: String
    let isBinary: Bool
}
