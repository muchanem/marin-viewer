import Foundation
import Observation

@Observable @MainActor
final class BookmarkModel {
    private(set) var scope: BookmarkScope?
    private(set) var entries: [SourceBookmark] = []
    var selectedID: UUID?
    var navigationError: String?
    @ObservationIgnored private let store: BookmarkStore

    init(preferences: UserDefaults) { store = BookmarkStore(preferences: preferences) }

    var rows: [BookmarkListEntry] {
        entries.enumerated().map { BookmarkListEntry(bookmark: $0.element, slot: $0.offset) }
    }

    func activate(_ scope: BookmarkScope?) {
        guard scope != self.scope else { return }
        self.scope = scope
        entries = scope.map(store.load) ?? []
        selectedID = nil
        navigationError = nil
    }

    func bookmark(in location: SourceLocation) -> SourceBookmark? { entries.first { $0.location == location } }
    func bookmark(at slot: Int) -> SourceBookmark? { entries.indices.contains(slot) ? entries[slot] : nil }

    func toggle(_ bookmark: SourceBookmark) {
        guard scope != nil else { return }
        if let existing = self.bookmark(in: bookmark.location) { remove(existing.id); return }
        entries.append(bookmark)
        persist()
    }

    func remove(_ id: UUID) {
        guard entries.contains(where: { $0.id == id }) else { return }
        entries.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        persist()
    }

    func update(_ bookmark: SourceBookmark) {
        guard let index = entries.firstIndex(where: { $0.id == bookmark.id }), entries[index] != bookmark else { return }
        entries[index] = bookmark
        persist()
    }

    /// SwiftUI's native reorder action supplies offsets in the original list.
    func move(from offsets: IndexSet, to destination: Int) {
        guard destination >= 0, destination <= entries.count,
              offsets.allSatisfy({ entries.indices.contains($0) }), !offsets.isEmpty else { return }
        let moved = offsets.sorted().map { entries[$0] }
        for offset in offsets.sorted(by: >) { entries.remove(at: offset) }
        let insertion = destination - offsets.count { $0 < destination }
        entries.insert(contentsOf: moved, at: insertion)
        persist()
    }

    func move(_ id: UUID, to slot: Int) {
        guard let current = entries.firstIndex(where: { $0.id == id }), entries.indices.contains(slot), slot != current else { return }
        move(from: IndexSet(integer: current), to: slot > current ? slot + 1 : slot)
    }

    private func persist() { if let scope { store.save(entries, for: scope) } }
}
