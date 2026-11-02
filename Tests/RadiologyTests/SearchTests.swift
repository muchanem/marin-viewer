import Foundation
import Testing
@testable import Radiology

actor MatchCollector {
    var matches: [SearchMatch] = []
    func append(_ values: [SearchMatch]) { matches.append(contentsOf: values) }
}

struct SearchTests {
    @Test func decodingPreservesByteOffsetsForUnicodeAndMultipleMatches() throws {
        let json = #"{"type":"match","data":{"path":{"text":"./A.swift"},"lines":{"text":"🙂 foo foo\n"},"line_number":3,"absolute_offset":30,"submatches":[{"start":5,"end":8},{"start":9,"end":12}]}}"#
        let results = try SearchMatch.decode(Data(json.utf8))
        #expect(results.count == 2)
        #expect(results[0].path == "A.swift")
        #expect(results[0].byteOffset == 35)
        #expect(results[1].column == 10)
        #expect(results[0].id != results[1].id)
    }

    @Test func argumentsProtectLeadingDashPatterns() {
        let options = SearchOptions(query: "--help", isRegex: false, includeGlob: "*.swift", excludeGlob: "Tests/**")
        #expect(options.arguments.suffix(3) == ["--", "--help", "."])
        #expect(options.arguments.contains("--fixed-strings"))
        #expect(options.arguments.contains("!Tests/**"))
    }

    @Test func realRipgrepSearchFindsUnicodeLiteralAndHonorsGlob() async throws {
        guard ToolLocator.executable("rg") != nil else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("🙂 needle\nNEEDLE\n".utf8).write(to: root.appending(path: "A.swift"))
        try Data("needle".utf8).write(to: root.appending(path: "B.md"))
        let collector = MatchCollector()
        let limited = try await SearchWorker().search(root: root, options: SearchOptions(query: "needle", includeGlob: "*.swift")) { await collector.append($0) }
        let results = await collector.matches
        #expect(!limited)
        #expect(results.count == 2)
        #expect(results[0].byteOffset == 5)
        #expect(results[0].path == "A.swift")
    }

    @Test func noMatchesAreNotAnErrorAndInvalidRegexIsReported() async throws {
        guard ToolLocator.executable("rg") != nil else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: root.appending(path: "file"))
        let limited = try await SearchWorker().search(root: root, options: SearchOptions(query: "absent")) { _ in }
        #expect(!limited)
        await #expect(throws: BrowserError.self) {
            try await SearchWorker().search(root: root, options: SearchOptions(query: "[", isRegex: true)) { _ in }
        }
    }
    @Test func resultLimitStopsTheProcessAndCapsDeliveredMatches() async throws {
        guard ToolLocator.executable("rg") != nil else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(String(repeating: "needle\n", count: 6000).utf8).write(to: root.appending(path: "large.txt"))
        let collector = MatchCollector()
        let limited = try await SearchWorker().search(root: root, options: SearchOptions(query: "needle")) { await collector.append($0) }
        #expect(limited)
        #expect(await collector.matches.count == SearchWorker.resultLimit)
    }

    @Test func cancelledSearchPropagatesCancellation() async throws {
        guard ToolLocator.executable("rg") != nil else { return }
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(String(repeating: "needle\n", count: 10000).utf8).write(to: root.appending(path: "large.txt"))
        let task = Task {
            try await SearchWorker().search(root: root, options: SearchOptions(query: "needle")) { _ in }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

}
