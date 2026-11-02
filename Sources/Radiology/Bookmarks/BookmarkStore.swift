import Foundation

@MainActor
final class BookmarkStore {
    static let key = "repositoryBookmarksV1"
    private let preferences: UserDefaults

    init(preferences: UserDefaults) { self.preferences = preferences }

    private func archive() -> [String: [SourceBookmark]] {
        guard let data = preferences.data(forKey: Self.key),
              let archive = try? JSONDecoder().decode([String: [SourceBookmark]].self, from: data) else { return [:] }
        return archive
    }

    func load(_ scope: BookmarkScope) -> [SourceBookmark] {
        var seen: Set<UUID> = []
        return (archive()[scope.key] ?? []).filter { $0.isValid && seen.insert($0.id).inserted }
    }

    func save(_ entries: [SourceBookmark], for scope: BookmarkScope) {
        var archive = archive()
        archive[scope.key] = entries
        guard let data = try? JSONEncoder().encode(archive) else { return }
        preferences.set(data, forKey: Self.key)
    }
}
