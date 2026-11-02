import Foundation
import Testing
@testable import Radiology

struct BookmarkTests {
    static func buffer() throws -> SourceBuffer {
        try SourceBuffer(path: "src/locations.rs", data: Data((0..<12).map { "fn point\($0)() {}" }.joined(separator: "\n").utf8))
    }

    @MainActor @Test func scopePersistenceReorderingAndDeletionKeepShortcutOrder() throws {
        let domain = "RadiologyTests.Bookmarks." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        let local = BookmarkScope(root: URL(filePath: "/tmp/repo-a"), pullRequest: nil)
        let pr1 = BookmarkScope(root: URL(filePath: "/tmp/repo-a"), pullRequest: 1)
        let pr2 = BookmarkScope(root: URL(filePath: "/tmp/repo-a"), pullRequest: 2)
        let other = BookmarkScope(root: URL(filePath: "/tmp/repo-b"), pullRequest: 1)
        let source = try Self.buffer()
        let model = BookmarkModel(preferences: preferences)
        model.activate(pr1)
        for line in 1...12 {
            model.toggle(SourceBookmark.make(in: source, at: source.byteOffset(line: line), label: "point\(line - 1)"))
        }
        let original = model.entries
        #expect(model.bookmark(at: 0)?.id == original[0].id && model.bookmark(at: 9)?.id == original[9].id)
        model.move(original[11].id, to: 0)
        #expect(model.bookmark(at: 0)?.id == original[11].id)
        #expect(model.bookmark(at: 9)?.id == original[8].id)
        model.move(from: IndexSet([0, 2]), to: 5)
        #expect(model.entries[3].id == original[11].id && model.entries[4].id == original[1].id)
        let reordered = model.entries
        for scope in [local, pr2, other] {
            model.activate(scope)
            #expect(model.entries.isEmpty)
            model.toggle(SourceBookmark.make(in: source, at: 0, label: "independent"))
        }
        let relaunched = BookmarkModel(preferences: preferences)
        relaunched.activate(pr1)
        #expect(relaunched.entries == reordered)
        relaunched.selectedID = reordered[0].id
        relaunched.remove(reordered[0].id)
        #expect(relaunched.selectedID == nil && relaunched.bookmark(at: 0)?.id == reordered[1].id)
        relaunched.toggle(reordered[1])
        #expect(!relaunched.entries.contains { $0.id == reordered[1].id }, "toggling an existing location removes it")
        relaunched.activate(local)
        #expect(relaunched.entries.count == 1 && relaunched.entries[0].label == "independent")
    }

    @Test func unicodeLocationsRelocateByAnchorAndRejectAmbiguousChanges() throws {
        let text = "fn café() {\r\n    let s = \"🚀\"; target();\r\n}\r\n"
        let original = try SourceBuffer(path: "unicode.rs", data: Data(text.utf8))
        let byte = try #require(text.range(of: "target").map { text[..<$0.lowerBound].utf8.count + 2 })
        let bookmark = SourceBookmark.make(in: original, at: byte, label: "café")
        #expect(try bookmark.resolve(in: original) == original.location(atByte: byte))
        let moved = try SourceBuffer(path: original.path, data: Data(("// inserted\n" + text).utf8))
        #expect(try bookmark.resolve(in: moved).byteOffset == byte + "// inserted\n".utf8.count)
        let ambiguous = try SourceBuffer(path: original.path, data: Data((text + text).utf8))
        #expect(throws: BrowserError.self) { try bookmark.resolve(in: ambiguous) }
        let edited = try SourceBuffer(path: original.path, data: Data(text.replacing("target", with: "changed").utf8))
        #expect(throws: BrowserError.self) { try bookmark.resolve(in: edited) }
        var before = original
        before.revision = .before
        #expect(throws: BrowserError.self) { try bookmark.resolve(in: before) }
    }

    @MainActor @Test func damagedStorageAndInvalidMovesDoNotCreateBookmarks() throws {
        let domain = "RadiologyTests.Bookmarks." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: domain))
        defer { preferences.removePersistentDomain(forName: domain) }
        preferences.set(Data("not json".utf8), forKey: BookmarkStore.key)
        let model = BookmarkModel(preferences: preferences)
        model.activate(BookmarkScope(root: URL(filePath: "/tmp/repo"), pullRequest: nil))
        #expect(model.entries.isEmpty)
        model.move(from: IndexSet(integer: 99), to: 0)
        let source = try Self.buffer()
        model.toggle(SourceBookmark.make(in: source, at: 0, label: "point"))
        let saved = model.entries
        model.move(from: IndexSet(integer: 0), to: 99)
        model.move(saved[0].id, to: -1)
        #expect(model.entries == saved)
        model.activate(nil)
        model.toggle(saved[0])
        #expect(model.entries.isEmpty)
    }
}
