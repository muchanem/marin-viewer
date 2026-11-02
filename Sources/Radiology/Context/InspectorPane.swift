import Foundation

enum InspectorPane: String, Sendable, Equatable, Identifiable {
    case references, definition, implementations, bookmarks
    var id: String { rawValue }

    var minimumHeight: Double {
        switch self {
        case .references: Theme.inspectorReferencesMinHeight
        case .definition, .implementations: Theme.inspectorDefinitionMinHeight
        case .bookmarks: Theme.inspectorBookmarksMinHeight
        }
    }
}
