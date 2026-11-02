import Foundation

extension AppModel {
    var canRefreshPR: Bool { isReviewing && !pullRequests.isLoading && !isOpening }
    func refreshCurrentPR() { if canRefreshPR { pullRequests.refreshCurrent() } }

    /// Resolve the latest reader after fetch, rechecking path/bytes if it moves
    /// during local blob/diff reads. No spelling-based symbol/path inference.
    func preparePRRefresh(old: PullRequestReview, new: PullRequestReview,
                          snapshot: RepositorySnapshot, store: ReviewRepository) async throws -> PRRefreshRestoration {
        while true {
            try Task.checkCancellation()
            guard let original = source else {
                if isLoadingSource && selectedPath != nil {
                    await awaitCurrentSourceLoad()
                    continue // recheck cancellation and the latest requested document
                }
                return PRRefreshRestoration(buffer: nil, caret: nil, viewportByte: nil, pins: .init(),
                    notice: selectedPath == nil ? nil : "Requested file could not be restored. Choose a changed file.")
            }
            let revision = original.revision ?? .after
            let oldSHA = revision == .after ? old.headSHA : old.baseSHA
            let newSHA = revision == .after ? new.headSHA : new.baseSHA
            let delta = oldSHA == newSHA ? [] : try await store.changes(base: oldSHA, head: newSHA)
            let rename = delta.first { change in
                if case .renamed = change.status { return change.oldPath == original.path }
                return false
            }
            let candidate = rename?.path ?? original.path
            let change = new.change(touching: candidate)
            var available = new.availableRevisions(for: candidate)
            if change == nil && new.blobIDs[candidate] == nil { available = [] }
            guard !available.isEmpty else {
                if source?.positionKey != original.positionKey || source?.data != original.data { continue }
                return PRRefreshRestoration(buffer: nil, caret: nil, viewportByte: nil, pins: .init(),
                                             notice: "Previously open file is absent from the refreshed PR. Choose a changed file.")
            }
            let chosen = available.contains(revision) ? revision : (available.contains(.after) ? .after : .before)
            let path = change?.path(in: chosen) ?? candidate
            let root: URL
            if chosen == .before, let change {
                root = try await store.materialize(blob: change.beforeBlob, path: path, revision: new.baseSHA)
            } else { root = new.headRoot }
            var fresh = try await SourceStore().load(root: root, path: path)
            fresh.revision = chosen
            let exact = fresh.data == original.data
            let lineMap: LineMap?
            if exact { lineMap = nil }
            else {
                let afterBlob = chosen == .after ? new.blobIDs[path] : change?.beforeBlob
                guard let afterBlob else { throw BrowserError.message("The refreshed file has no proven source blob.") }
                let comparison = FileChange(path: path, oldPath: nil, status: .modified,
                    beforeBlob: ContentDigest.blobID(of: original.data), afterBlob: afterBlob, additions: 0, deletions: 0)
                lineMap = LineMap(try await store.lineChanges(base: oldSHA, head: newSHA, change: comparison))
            }
            try Task.checkCancellation()
            guard source?.positionKey == original.positionKey, source?.data == original.data else { continue }
            // Read caret, viewport and pins NOW, not at Refresh click time.
            let caret = currentCaretLocation(in: original) ?? original.location(atByte: 0)
            let viewport = positions[original.positionKey]?.byteOffset ?? caret.byteOffset
            func mapped(_ byte: Int) -> Int {
                if exact { return min(byte, fresh.data.count) }
                let oldLine = original.line(atByte: byte)
                let line = min(max(1, lineMap!.map(line: oldLine, from: .before)), fresh.lineCount)
                let oldRange = original.lineByteRange(oldLine)
                let newRange = fresh.lineByteRange(line)
                if original.data[oldRange] == fresh.data[newRange] {
                    return newRange.lowerBound + min(max(0, byte - oldRange.lowerBound), newRange.count)
                }
                return fresh.byteOffset(line: line)
            }
            let identity = SourceContentIdentity(fresh.data)
            let pins = exact ? occurrencePins.retainingDocument(from: original.positionKey, to: fresh.positionKey, identity: identity) : .init()
            return PRRefreshRestoration(buffer: fresh, caret: fresh.location(atByte: mapped(caret.byteOffset)),
                viewportByte: mapped(viewport), pins: pins,
                notice: chosen != revision ? "This file is now available in \(chosen.title); showing that revision." : nil)
        }
    }
}
