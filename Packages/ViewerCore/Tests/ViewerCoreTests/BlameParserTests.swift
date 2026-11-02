import Foundation
import Testing
@testable import ViewerCore

struct BlameParserTests {
    /// `git blame --porcelain 01a8bb8 -- <path>` against `demo/pr10640.json`'s
    /// `blame` arrays (ten-character SHAs) and commit table.
    @Test(arguments: [
        ("src_shellbox_backends_local_machine.py.blame", "lib/shellbox/src/shellbox/backends/local/machine.py"),
        ("src_shellbox_http_service.py.blame", "lib/shellbox/src/shellbox/http_service.py"),
    ])
    func matchesTheDemoData(fixture: String, path: String) throws {
        let blame = try BlameParser.parse(try Fixtures.text("pr10640/" + fixture))
        let expected = try Fixtures.expectedFile(path)["blame"] as! [String]
        #expect(blame.lineSHAs.map { String($0.prefix(10)) } == expected)
        #expect(blame.lineSHAs.allSatisfy { $0.count == 40 })

        let table = try Fixtures.expected()["commits"] as! [String: [String: Any]]
        for sha in Set(blame.lineSHAs) {
            let commit = try #require(blame.commits[sha])
            let demo = try #require(table[String(sha.prefix(10))])
            #expect(commit.author == demo["author"] as? String)
            #expect(commit.time == demo["time"] as? Int)
            #expect(commit.summary == demo["summary"] as? String)
        }

        // Every head line of the diff has blame, and only head lines do.
        let diff = try DiffRows.parse(try Fixtures.text("pr10640/" + fixture.replacingOccurrences(of: ".blame", with: ".diff")))
        #expect(blame.lineSHAs.count == diff.rows.compactMap(\.newLine).count)
    }

    @Test func gutterTextMatchesTheDemo() throws {
        let blame = try BlameParser.parse(try Fixtures.text("pr10640/src_shellbox_http_service.py.blame"))
        let commit = try #require(blame.commit(forNewLine: 1))
        // The demo measures age from Date.parse("2026-11-01"), midnight UTC.
        let now = Date(timeIntervalSince1970: 1_793_491_200)
        let days = max(0, Int(((1_793_491_200 - Double(commit.time)) / 86_400 + 0.5).rounded(.down)))
        #expect(commit.gutterLabel(at: now) == "\(commit.sha.prefix(7)) \(commit.author.split(separator: " ")[0]) · \(days)d")
        #expect(commit.tooltip == "\(commit.sha.prefix(10)) \(commit.summary)")
        #expect(BlameCommit(sha: "a", author: "Ada", time: 2_000_000_000, summary: "").ageInDays(at: now) == 0, "never negative")
        #expect(BlameCommit(sha: "a", author: "", time: 0, summary: "").firstName == "")
    }

    @Test func runsOverTheWholeFile() throws {
        let blame = Blame(lineSHAs: ["A", "A", "B", "A", "A", "A"], commits: [:])
        #expect(blame.runs == [
            BlameRun(sha: "A", lines: 1...2), BlameRun(sha: "B", lines: 3...3), BlameRun(sha: "A", lines: 4...6),
        ])
        #expect(Blame(lineSHAs: [], commits: [:]).runs.isEmpty)
        let real = try BlameParser.parse(try Fixtures.text("pr10640/src_shellbox_backends_local_machine.py.blame"))
        #expect(real.runs.map(\.lines.count).reduce(0, +) == 1281)
    }

    /// Deleted rows are transparent to a run; a gap ends it.
    @Test func labelsFollowVisibleRows() {
        // c1 c2 d a3 c4 | gap c5 | c6 c7
        let rows = Fixtures.rows("ccdacccc")
        #expect(rows.map(\.newLine) == [1, 2, nil, 3, 4, 5, 6, 7])
        let blame = Blame(lineSHAs: ["A", "A", "B", "A", "A", "A", "C"], commits: [:])
        let labeled = blame.labeledRows(rows, segments: [.rows(0..<5), .gap(DiffGap(rows: 5..<6, rowCount: 8)), .rows(6..<8)])
        // Row 3 (new 3, B) differs from row 1 across the deletion; row 4 is A
        // again. Row 6 starts after the gap; row 7 is C.
        #expect(Array(labeled) == [0, 3, 4, 6, 7])
    }

    @Test func malformedOrIncompleteOutputIsAnError() {
        #expect(throws: BlameParseError.malformedHeader("not a header")) { try BlameParser.parse("not a header\n") }
        let sha = String(repeating: "a", count: 40)
        #expect(throws: BlameParseError.missingLine(1)) { try BlameParser.parse("\(sha) 2 2 1\nauthor A\n\tx\n") }
        // --line-porcelain repeats the keys; the first value wins.
        let blame = try? BlameParser.parse("\(sha) 1 1 2\nauthor A\nsummary s\n\tx\n\(sha) 2 2\nauthor A\nsummary s\n\ty\n")
        #expect(blame?.lineSHAs == [sha, sha])
        #expect(blame?.commits[sha] == BlameCommit(sha: sha, author: "A", time: 0, summary: "s"))
    }
}
