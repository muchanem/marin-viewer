import Foundation

/// Which side of a pull request a document comes from. `before` is the
/// merge base with the base branch; `after` is the pinned head commit. The
/// same repository-relative path names two different documents, so the
/// revision travels with locations, buffers, and restoration points.
enum ReviewRevision: String, Hashable, Sendable, Codable, CaseIterable, Identifiable {
    case before, after
    var id: Self { self }

    var title: String {
        switch self {
        case .before: "Before"
        case .after: "After"
        }
    }

    var other: ReviewRevision { self == .before ? .after : .before }
}
