import Foundation

/// App-wide display preferences. These never reset contextual selections or
/// alter semantic work, source navigation, bookmarks, or repository state.
struct InspectorPanes: Equatable {
    var references = true
    var definition = true
    var implementations = true
    var bookmarks = true
    static let all = InspectorPanes()
    static let preferencesPrefix = "contextPane."

    init() {}

    init(preferences: UserDefaults) {
        func enabled(_ pane: InspectorPane) -> Bool {
            let key = Self.preferencesPrefix + pane.rawValue
            return preferences.object(forKey: key) == nil || preferences.bool(forKey: key)
        }
        references = enabled(.references)
        definition = enabled(.definition)
        implementations = enabled(.implementations)
        bookmarks = enabled(.bookmarks)
    }

    func save(to preferences: UserDefaults) {
        preferences.set(references, forKey: Self.preferencesPrefix + InspectorPane.references.rawValue)
        preferences.set(definition, forKey: Self.preferencesPrefix + InspectorPane.definition.rawValue)
        preferences.set(implementations, forKey: Self.preferencesPrefix + InspectorPane.implementations.rawValue)
        preferences.set(bookmarks, forKey: Self.preferencesPrefix + InspectorPane.bookmarks.rawValue)
    }

    var enabledCount: Int { [references, definition, implementations, bookmarks].count { $0 } }
    var areAllEnabled: Bool { self == .all }

    /// Definition/outline and implementations share the middle pane. Disabling
    /// implementations reveals the definition when that preference is enabled.
    func visiblePanes(hasTrait: Bool) -> [InspectorPane] {
        var result: [InspectorPane] = []
        if references { result.append(.references) }
        if implementations, hasTrait { result.append(.implementations) }
        else if definition { result.append(.definition) }
        if bookmarks { result.append(.bookmarks) }
        return result
    }
}
