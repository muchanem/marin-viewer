import Foundation

/// The commit fields the blame gutter shows: author, author time, summary.
public struct BlameCommit: Hashable, Sendable, Codable {
    public let sha: String
    public let author: String
    /// `author-time`, seconds since 1970.
    public let time: Int
    public let summary: String

    public init(sha: String, author: String, time: Int, summary: String) {
        self.sha = sha
        self.author = author
        self.time = time
        self.summary = summary
    }

    /// The gutter's seven-character SHA.
    public var shortSHA: String { String(sha.prefix(7)) }
    /// The author's first word, as the gutter shows it.
    public var firstName: String { String(author.split(separator: " ", maxSplits: 1).first ?? "") }

    /// Whole days from the author time to `now`, rounded half up as the
    /// demo's `Math.round`, and never negative.
    public func ageInDays(at now: Date) -> Int {
        let days = (now.timeIntervalSince1970 - Double(time)) / 86_400
        return max(0, Int((days + 0.5).rounded(.down)))
    }

    /// "97704d9 Russell · 61d".
    public func gutterLabel(at now: Date) -> String {
        "\(shortSHA) \(firstName) · \(ageInDays(at: now))d"
    }

    /// The tooltip: ten-character SHA and summary, as in the demo.
    public var tooltip: String { "\(sha.prefix(10)) \(summary)" }
}

/// Consecutive head lines last changed by the same commit.
public struct BlameRun: Hashable, Sendable {
    public let sha: String
    public let lines: ClosedRange<Int>
}

/// `git blame --porcelain` for one file at one commit: the commit of every
/// head line plus the commit table.
public struct Blame: Hashable, Sendable {
    /// Full SHA of each line; index 0 is line 1.
    public let lineSHAs: [String]
    public let commits: [String: BlameCommit]

    public init(lineSHAs: [String], commits: [String: BlameCommit]) {
        self.lineSHAs = lineSHAs
        self.commits = commits
    }

    public func sha(forNewLine line: Int) -> String? {
        lineSHAs.indices.contains(line - 1) ? lineSHAs[line - 1] : nil
    }

    public func commit(forNewLine line: Int) -> BlameCommit? {
        sha(forNewLine: line).flatMap { commits[$0] }
    }

    /// Runs over the whole head file, for a reader with no gaps.
    public var runs: [BlameRun] {
        var runs: [BlameRun] = []
        var start = 0
        for index in lineSHAs.indices where index + 1 == lineSHAs.count || lineSHAs[index + 1] != lineSHAs[index] {
            runs.append(BlameRun(sha: lineSHAs[index], lines: (start + 1)...(index + 1)))
            start = index + 1
        }
        return runs
    }

    /// The rows of a diff card that carry a gutter label: the first row of
    /// each run of one SHA, as the demo's `lineHTML` decides it. Deleted rows
    /// have no blame and do not break a run; a gap does, so the first row
    /// after a gap is always labeled.
    public func labeledRows(_ rows: [DiffRow], segments: [DiffSegment]) -> IndexSet {
        var labeled = IndexSet()
        for segment in segments {
            guard case .rows(let range) = segment else { continue }
            var last: String?
            for index in range {
                guard let line = rows[index].newLine, let sha = sha(forNewLine: line) else { continue }
                if sha != last { labeled.insert(index) }
                last = sha
            }
        }
        return labeled
    }
}

public enum BlameParseError: Error, Equatable, Sendable {
    case malformedHeader(String)
    /// Some line between 1 and the last one had no entry.
    case missingLine(Int)
}

/// Parses `git blame --porcelain` (or `--line-porcelain`) output.
///
/// Each entry is a header `<sha> <orig-line> <final-line> [<group-size>]`,
/// then `key value` lines (only the first time a commit appears, unless
/// `--line-porcelain`), then the line's content after a tab. Lines are
/// placed by their final line number rather than output order.
public enum BlameParser {
    public static func parse(_ porcelain: String) throws -> Blame {
        var shaByLine: [Int: String] = [:]
        var fields: [String: [String: String]] = [:]
        var current: String?
        for raw in porcelain.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            if raw.first == UInt8(ascii: "\t") {
                current = nil
                continue
            }
            let line = String(decoding: raw, as: UTF8.self)
            if let sha = current {
                let key = line.prefix { $0 != " " }
                let value = line.dropFirst(key.count).dropFirst()
                if fields[sha, default: [:]][String(key)] == nil { fields[sha, default: [:]][String(key)] = String(value) }
                continue
            }
            let parts = line.split(separator: " ")
            guard parts.count >= 3, parts[0].count == 40 || parts[0].count == 64,
                  parts[0].allSatisfy(\.isHexDigit), let final = Int(parts[2]), final >= 1
            else { throw BlameParseError.malformedHeader(line) }
            let sha = String(parts[0])
            shaByLine[final] = sha
            current = sha
        }
        let count = shaByLine.keys.max() ?? 0
        var lineSHAs: [String] = []
        lineSHAs.reserveCapacity(count)
        for line in stride(from: 1, through: count, by: 1) {
            guard let sha = shaByLine[line] else { throw BlameParseError.missingLine(line) }
            lineSHAs.append(sha)
        }
        var commits: [String: BlameCommit] = [:]
        for (sha, values) in fields {
            commits[sha] = BlameCommit(
                sha: sha, author: values["author"] ?? "", time: Int(values["author-time"] ?? "") ?? 0,
                summary: values["summary"] ?? "")
        }
        return Blame(lineSHAs: lineSHAs, commits: commits)
    }
}
