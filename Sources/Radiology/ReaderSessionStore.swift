import Foundation

/// Preference persistence is separate from asynchronous repository preparation.
@MainActor
final class ReaderSessionStore {
    static let key = "lastReaderSession"
    private let preferences: UserDefaults

    init(preferences: UserDefaults) { self.preferences = preferences }

    func load() -> ReaderSession? {
        guard let data = preferences.data(forKey: Self.key),
              let session = try? JSONDecoder().decode(ReaderSession.self, from: data), session.isValid else { return nil }
        return session
    }

    func save(_ session: ReaderSession) {
        guard session.isValid, let data = try? JSONEncoder().encode(session) else { return }
        preferences.set(data, forKey: Self.key)
    }
}
