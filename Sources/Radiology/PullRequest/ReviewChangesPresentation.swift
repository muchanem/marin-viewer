import Foundation

/// Sidebar projection only: canonical review data and source order are unchanged.
struct ReviewChangesPresentation: Equatable {
    let totalCount: Int
    let changes: [FileChange]
    var isGenuinelyEmpty: Bool { totalCount == 0 }
    var isFilteredEmpty: Bool { totalCount > 0 && changes.isEmpty }
    var additions: Int { changes.compactMap(\.additions).reduce(0, +) }
    var deletions: Int { changes.compactMap(\.deletions).reduce(0, +) }
    var fileCountLabel: String { "\(changes.count) of \(totalCount) files" }

    init(changes: [FileChange], filters: SourceFilters) {
        totalCount = changes.count
        self.changes = changes.filter { change in
            ReviewRevision.allCases.contains { revision in
                change.path(in: revision).map(filters.includes) ?? false
            }
        }
    }

    func selectionID(path: String?, revision: ReviewRevision?) -> String? {
        guard let path, let revision else { return nil }
        return changes.first { $0.path(in: revision) == path }?.id
    }
}
