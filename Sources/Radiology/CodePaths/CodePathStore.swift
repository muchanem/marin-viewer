import Foundation

@MainActor
final class CodePathStore {
    static let key = "repositoryCodePathsV1"
    private let preferences: UserDefaults

    init(preferences: UserDefaults) { self.preferences = preferences }

    private func archive() throws -> [String: [CodePath]] {
        guard let data = preferences.data(forKey: Self.key) else { return [:] }
        return try JSONDecoder().decode([String: [CodePath]].self, from: data)
    }

    func load(repositoryPath: String) throws -> [CodePath] {
        var seen: Set<UUID> = []
        return try (archive()[repositoryPath] ?? []).filter { $0.isValid && seen.insert($0.id).inserted }
    }

    func save(_ paths: [CodePath], repositoryPath: String) throws {
        var archive = try archive()
        archive[repositoryPath] = paths
        preferences.set(try JSONEncoder().encode(archive), forKey: Self.key)
    }
}
