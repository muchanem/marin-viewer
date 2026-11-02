import Foundation

/// One hunk of a `git diff -U0` between the Before and After documents of
/// one path. Lines are one-based. A side with zero lines (`-0,0` or `+c,0`)
/// has an empty range anchored where the change sits; git's convention for
/// an empty side is the line *before* which the other side's lines appear.
struct DiffHunk: Equatable, Sendable {
    let beforeStart: Int
    let beforeCount: Int
    let afterStart: Int
    let afterCount: Int

    /// Before lines removed by this hunk, one-based, half-open.
    var removedLines: Range<Int> { beforeStart..<(beforeStart + beforeCount) }
    /// After lines added by this hunk, one-based, half-open.
    var addedLines: Range<Int> { afterStart..<(afterStart + afterCount) }
}

/// Line-level changes of one path between the two revisions, parsed from
/// git's own unified output. Git splits lines on `\n` exactly as
/// `SourceBuffer` does, so `\r\n` endings and any Unicode content need no
/// special handling here: a line number is a line number on both sides.
struct FileLineChanges: Equatable, Sendable {
    let hunks: [DiffHunk]
    let isBinary: Bool

    static let none = FileLineChanges(hunks: [], isBinary: false)
    static let binary = FileLineChanges(hunks: [], isBinary: true)

    /// Changed line ranges on one side: added lines in After, removed lines
    /// in Before. Sorted, non-empty, disjoint.
    func changedLines(in revision: ReviewRevision) -> [Range<Int>] {
        hunks.map { revision == .after ? $0.addedLines : $0.removedLines }.filter { !$0.isEmpty }
    }

    /// Where a change is anchored on one side even when that side has no
    /// lines of its own (a pure deletion seen from After, or a pure
    /// insertion seen from Before): the first line of the hunk's own lines,
    /// or the line after which the other side's lines would appear.
    func changeAnchors(in revision: ReviewRevision) -> [Int] {
        hunks.map { hunk in
            let range = revision == .after ? hunk.addedLines : hunk.removedLines
            if !range.isEmpty { return range.lowerBound }
            return max(1, (revision == .after ? hunk.afterStart : hunk.beforeStart) + 1)
        }
    }

    var additions: Int { hunks.reduce(0) { $0 + $1.afterCount } }
    var deletions: Int { hunks.reduce(0) { $0 + $1.beforeCount } }
}

enum UnifiedDiffParser {
    /// Parses the output of `git diff -U0 … -- path`. Only hunk headers and
    /// the binary marker matter; context, `\ No newline at end of file`,
    /// index and mode lines are skipped. A malformed header is an error
    /// rather than a guess, so a surprising git version cannot silently
    /// mis-highlight a file.
    static func parse(_ text: String) throws -> FileLineChanges {
        var hunks: [DiffHunk] = []
        // Split on the byte, not the Character: Swift folds "\r\n" into one
        // grapheme, which would glue a hunk header to a preceding CRLF line.
        for rawLine in text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            var line = Substring(String(decoding: rawLine, as: UTF8.self))
            if line.hasSuffix("\r") { line = line.dropLast() }
            if line.hasPrefix("Binary files ") && line.hasSuffix(" differ") { return .binary }
            guard line.hasPrefix("@@ ") else { continue }
            hunks.append(try hunk(fromHeader: line))
        }
        return FileLineChanges(hunks: hunks, isBinary: false)
    }

    /// `@@ -a[,b] +c[,d] @@ …`. A missing count means 1.
    static func hunk(fromHeader header: Substring) throws -> DiffHunk {
        let fields = header.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard fields.count >= 3, fields[0] == "@@", fields[1].hasPrefix("-"), fields[2].hasPrefix("+") else {
            throw BrowserError.message("Unrecognized diff hunk header: \(header)")
        }
        let before = try side(fields[1].dropFirst())
        let after = try side(fields[2].dropFirst())
        return DiffHunk(beforeStart: before.start, beforeCount: before.count, afterStart: after.start, afterCount: after.count)
    }

    private static func side(_ text: Substring) throws -> (start: Int, count: Int) {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(parts[0]), start >= 0 else { throw BrowserError.message("Unrecognized diff range: \(text)") }
        if parts.count == 1 { return (start, 1) }
        guard parts.count == 2, let count = Int(parts[1]), count >= 0 else { throw BrowserError.message("Unrecognized diff range: \(text)") }
        return (start, count)
    }
}

/// Maps one-based lines between the two revisions of one path through its
/// hunks. A line outside every hunk shifts by the lines added and removed
/// before it; a line inside a hunk lands on the hunk's first line on the
/// other side, so toggling Before/After keeps the reader at the same change.
struct LineMap: Sendable {
    let hunks: [DiffHunk]

    init(_ changes: FileLineChanges) { hunks = changes.hunks }

    func map(line: Int, from source: ReviewRevision) -> Int {
        var delta = 0
        for hunk in hunks {
            let own = source == .before ? hunk.removedLines : hunk.addedLines
            let other = source == .before ? hunk.addedLines : hunk.removedLines
            let ownAnchor = source == .before ? hunk.beforeStart : hunk.afterStart
            let otherAnchor = source == .before ? hunk.afterStart : hunk.beforeStart
            if own.contains(line) {
                // Inside the change: the other side's first changed line, or
                // the line after which the change would have been.
                return other.isEmpty ? max(1, otherAnchor + 1) : other.lowerBound
            }
            let ownEnd = own.isEmpty ? ownAnchor : own.upperBound - 1
            if line > ownEnd {
                delta += other.count - own.count
            } else {
                break
            }
        }
        return max(1, line + delta)
    }
}
