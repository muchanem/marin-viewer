import Foundation

@MainActor
final class IndexingPersonalityPreferences {
    private let preferences: UserDefaults
    init(preferences: UserDefaults) { self.preferences = preferences }
    private func key(_ root: URL) -> String { "indexingPersonality." + IndexCache.repositoryID(for: root) }
    func load(for root: URL) -> IndexingPersonality {
        preferences.string(forKey: key(root)).flatMap(IndexingPersonality.init(rawValue:)) ?? .default
    }
    func save(_ personality: IndexingPersonality, for root: URL) { preferences.set(personality.rawValue, forKey: key(root)) }
}
