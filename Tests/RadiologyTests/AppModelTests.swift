import Foundation
import Testing
@testable import Radiology

@MainActor
struct AppModelTests {
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(), "Async model operation timed out")
    }

    @Test func latestNavigationWinsAndBackRestoresScrollLocation() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("first\nsecond\nthird".utf8).write(to: root.appending(path: "A.swift"))
        try Data("other".utf8).write(to: root.appending(path: "B.swift"))
        let suiteName = "RadiologyTests." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: preferences)
        model.openRepository(root)
        try await waitUntil { !model.isOpening }
        model.openFile("A.swift")
        try await waitUntil { !model.isLoadingSource }
        model.updatePosition(path: "A.swift", byteOffset: 13, line: 3)
        model.openFile("B.swift")
        try await waitUntil { !model.isLoadingSource }
        model.goBack()
        try await waitUntil { !model.isLoadingSource }
        #expect(model.source?.path == "A.swift")
        #expect(model.navigationTarget?.byteOffset == 13)
        #expect(model.currentLine == 3)
        model.openFile("B.swift")
        model.navigate(to: SourceLocation(path: "A.swift", byteOffset: 6))
        try await waitUntil { !model.isLoadingSource }
        #expect(model.source?.path == "A.swift")
        #expect(model.navigationTarget?.byteOffset == 6)
        #expect(model.currentLine == 2)
    }

    @Test func passiveScrollingDoesNotReplaceCommittedStructuralTrail() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("one\ntwo\nthree\n".utf8).write(to: root.appending(path: "A.rs"))
        try Data("other\n".utf8).write(to: root.appending(path: "B.rs"))
        let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
        let model = AppModel(preferences: preferences)
        model.openRepository(root)
        try await waitUntil { !model.isOpening }
        model.openFile("A.rs")
        try await waitUntil { !model.isLoadingSource }
        model.updatePosition(path: "A.rs", byteOffset: 8, line: 3)
        model.navigate(to: SourceLocation(path: "A.rs", byteOffset: 0))
        model.updatePosition(path: "A.rs", byteOffset: 4, line: 2)
        model.navigate(to: SourceLocation(path: "B.rs", byteOffset: 0))
        model.goBack()
        #expect(model.navigationTarget == SourceLocation(path: "A.rs", byteOffset: 0))
        model.goBack()
        #expect(model.navigationTarget == SourceLocation(path: "A.rs", byteOffset: 8))
    }

    @Test func repeatedOutlineActivationAlwaysIssuesAJumpAndRestartsHighlight() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("fn target() {}\n".utf8).write(to: root.appending(path: "A.rs"))
        let preferences = try #require(UserDefaults(suiteName: "RadiologyTests." + UUID().uuidString))
        let model = AppModel(preferences: preferences)
        model.openRepository(root)
        try await waitUntil { !model.isOpening }
        model.openFile("A.rs")
        try await waitUntil { !model.isLoadingSource }
        let symbol = DocumentSymbol(name: "target", kind: "function", byteRange: 0..<14,
                                    selectionByteRange: 3..<9, depth: 0)
        model.commit(symbol, highlight: true)
        let firstNavigation = model.navigationRevision
        let firstHighlight = model.jumpHighlightRevision
        let historyCount = model.history.entries.count
        model.commit(symbol, highlight: true)
        #expect(model.navigationRevision == firstNavigation + 1)
        #expect(model.jumpHighlightRevision == firstHighlight + 1)
        #expect(model.history.entries.count == historyCount, "Repeated activation should restart feedback without duplicating history")
    }

    @Test func aNewRepositoryClearsOldStateAndWinsAnOpeningRace() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let a = base.appending(path: "A")
        let b = base.appending(path: "B")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data().write(to: a.appending(path: "first.swift"))
        try Data().write(to: b.appending(path: "last.swift"))
        let suiteName = "RadiologyTests." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: preferences)
        model.openRepository(a)
        model.openRepository(b)
        try await waitUntil { !model.isOpening }
        #expect(model.repository?.root.lastPathComponent == "B")
        #expect(model.repository?.files.map(\.path) == ["last.swift"])
        #expect(model.history.entries.isEmpty)
        #expect(model.source == nil)
        #expect(model.repositoryError == nil)
    }

    @Test func supersededParseCannotRepaintTheNextFile() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let large = (0..<2_000).map { "func old\($0)() { print(\($0)) }" }.joined(separator: "\n")
        try Data(large.utf8).write(to: root.appending(path: "Old.swift"))
        try Data("struct Current {}".utf8).write(to: root.appending(path: "Current.swift"))
        let suiteName = "RadiologyTests." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: preferences)
        model.openRepository(root)
        try await waitUntil { !model.isOpening }
        model.openFile("Old.swift")
        model.openFile("Current.swift")
        try await waitUntil { model.source?.path == "Current.swift" && !model.isParsingSource }
        #expect(model.syntax?.path == "Current.swift")
        #expect(model.syntax?.symbols.contains { $0.name == "Current" } == true)
    }

    /// Switching between files of different languages must not leak the
    /// previous grammar's snapshot into the newly opened file.
    @Test func switchingLanguagesReplacesTheSnapshotAndItsGrammar() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("struct Scan {}\n".utf8).write(to: root.appending(path: "Scan.swift"))
        try Data("fn main() { println!(\"hi\"); }\n".utf8).write(to: root.appending(path: "main.rs"))
        try Data("# notes\n".utf8).write(to: root.appending(path: "NOTES.md"))
        let suiteName = "RadiologyTests." + UUID().uuidString
        let preferences = try #require(UserDefaults(suiteName: suiteName))
        defer { preferences.removePersistentDomain(forName: suiteName) }
        let model = AppModel(preferences: preferences)
        model.openRepository(root)
        try await waitUntil { !model.isOpening }

        model.openFile("Scan.swift")
        try await waitUntil { model.syntax?.path == "Scan.swift" }
        #expect(model.syntax?.languageID == "swift")

        model.openFile("main.rs")
        try await waitUntil { model.syntax?.path == "main.rs" }
        #expect(model.syntax?.languageID == "rust")
        #expect(model.syntax?.symbols.contains { $0.name == "main" } == true)

        // An unsupported file clears the snapshot and leaves readable text.
        model.openFile("NOTES.md")
        try await waitUntil { model.source?.path == "NOTES.md" }
        #expect(model.syntax == nil)
        #expect(model.syntaxError == nil)
        #expect(model.source?.text == "# notes\n")
    }
}
