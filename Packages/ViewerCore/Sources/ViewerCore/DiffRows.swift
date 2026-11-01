import Foundation

/// One row of the diffs-first reader: a line both revisions share, a line
/// the head added, or a line the base had and the head deleted. Line
/// numbers are one-based; an added row has no old line and a deleted row no
/// new line. This is one `[tag, old, new, text]` entry of `lines` in
/// `demo/pr10640.json`.
public struct DiffRow: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case context = "c"
        case added = "a"
        case deleted = "d"
    }

    public let kind: Kind
    public let oldLine: Int?
    public let newLine: Int?
    public let text: String

    public init(kind: Kind, oldLine: Int?, newLine: Int?, text: String) {
        self.kind = kind
        self.oldLine = oldLine
        self.newLine = newLine
        self.text = text
    }

    /// Added or deleted: the rows the diff view keeps context around.
    public var isChange: Bool { kind != .context }
}

/// What happened to a path, with `git diff --name-status` letters.
public enum FileChangeStatus: String, Hashable, Sendable {
    case added = "A"
    case deleted = "D"
    case modified = "M"
    case renamed = "R"
    case copied = "C"
}

/// One file of a unified diff: its paths, status and rows. A binary file,
/// a pure rename and a mode change have no rows; the reader shows the first
/// as a placeholder and builds the others with `DiffRows.unchanged(_:)`.
public struct FileDiff: Hashable, Sendable {
    /// Nil when the file is new.
    public var oldPath: String?
    /// Nil when the file was deleted.
    public var newPath: String?
    public var status: FileChangeStatus
    /// Git's similarity index for renames and copies, in percent.
    public var similarity: Int?
    public var isBinary: Bool
    public var oldMode: String?
    public var newMode: String?
    public var rows: [DiffRow]

    public init(
        oldPath: String?, newPath: String?, status: FileChangeStatus, similarity: Int? = nil,
        isBinary: Bool = false, oldMode: String? = nil, newMode: String? = nil, rows: [DiffRow] = []
    ) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.status = status
        self.similarity = similarity
        self.isBinary = isBinary
        self.oldMode = oldMode
        self.newMode = newMode
        self.rows = rows
    }

    /// The path the reader shows: the new one, or the old one for a deletion.
    public var path: String { newPath ?? oldPath ?? "" }
    public var additions: Int { rows.count { $0.kind == .added } }
    public var deletions: Int { rows.count { $0.kind == .deleted } }

    /// The first row whose new-side line is `line`, as the demo's
    /// `findIndex(l => l[2] === n)`. Deleted rows never match.
    public func rowIndex(forNewLine line: Int) -> Int? {
        rows.firstIndex { $0.newLine == line }
    }
}

public enum DiffParseError: Error, Equatable, Sendable {
    case malformedHunkHeader(String)
    /// A hunk ended before its header's line counts were used up.
    case truncatedHunk(String)
}

/// Builds `FileDiff` rows from `git diff` output, the way `demo/extract.py`
/// builds `lines`. Meant for whole-file diffs (`-U<large>`), but any context
/// size parses: each hunk restarts the line counters from its header.
///
/// Like Radiology's `UnifiedDiffParser`, lines split on the `\n` byte, so a
/// CRLF line never glues onto the next one; the trailing `\r` is dropped
/// from row text, which matches the demo's text-mode read. Hunk bodies are
/// bounded by the header's counts, so a body line such as `--- x` or
/// `+++ y` is never mistaken for a header.
public enum DiffRows {
    /// Parses the diff of one file. Text without any file header yields an
    /// empty modified file.
    public static func parse(_ text: String) throws -> FileDiff {
        try parseFiles(text).first ?? FileDiff(oldPath: nil, newPath: nil, status: .modified)
    }

    /// Parses every file of a multi-file `git diff`, in output order.
    public static func parseFiles(_ text: String) throws -> [FileDiff] {
        var files: [FileDiff] = []
        var current: FileDiff?
        var lines = splitLines(text)[...]
        while let line = lines.popFirst() {
            if line.hasPrefix("diff --git ") {
                if let file = current { files.append(finish(file)) }
                let paths = gitHeaderPaths(line.dropFirst("diff --git ".count))
                current = FileDiff(oldPath: paths?.old, newPath: paths?.new, status: .modified)
                continue
            }
            var file = current ?? FileDiff(oldPath: nil, newPath: nil, status: .modified)
            if line.hasPrefix("@@ ") {
                try readHunk(header: line, from: &lines, into: &file)
            } else {
                readHeaderLine(line, into: &file)
            }
            current = file
        }
        if let file = current { files.append(finish(file)) }
        return files
    }

    /// All-context rows for a file whose text did not change (a pure rename
    /// or a mode change), so the reader can still show it.
    public static func unchanged(_ text: String) -> [DiffRow] {
        var lines = splitLines(text)
        if lines.last == "" { lines.removeLast() }
        return lines.enumerated().map { DiffRow(kind: .context, oldLine: $0.offset + 1, newLine: $0.offset + 1, text: $0.element) }
    }

    // MARK: - Lines

    private static func splitLines(_ text: String) -> [String] {
        text.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false).map { raw in
            var bytes = raw
            if bytes.last == UInt8(ascii: "\r") { bytes = bytes.dropLast() }
            return String(decoding: bytes, as: UTF8.self)
        }
    }

    private static func readHunk(header: String, from lines: inout ArraySlice<String>, into file: inout FileDiff) throws {
        let hunk = try hunkStarts(header)
        var old = hunk.oldStart, new = hunk.newStart
        var oldLeft = hunk.oldCount, newLeft = hunk.newCount
        while oldLeft > 0 || newLeft > 0 {
            guard let line = lines.popFirst() else { throw DiffParseError.truncatedHunk(header) }
            let text = String(line.dropFirst())
            switch line.first {
            case "\\":
                continue
            case " ", nil:
                // An empty line is a context line whose leading space was stripped.
                guard oldLeft > 0, newLeft > 0 else { throw DiffParseError.truncatedHunk(header) }
                file.rows.append(DiffRow(kind: .context, oldLine: old, newLine: new, text: text))
                old += 1; new += 1; oldLeft -= 1; newLeft -= 1
            case "-":
                guard oldLeft > 0 else { throw DiffParseError.truncatedHunk(header) }
                file.rows.append(DiffRow(kind: .deleted, oldLine: old, newLine: nil, text: text))
                old += 1; oldLeft -= 1
            case "+":
                guard newLeft > 0 else { throw DiffParseError.truncatedHunk(header) }
                file.rows.append(DiffRow(kind: .added, oldLine: nil, newLine: new, text: text))
                new += 1; newLeft -= 1
            default:
                throw DiffParseError.truncatedHunk(header)
            }
        }
    }

    /// `@@ -a[,b] +c[,d] @@ …`. A missing count means 1.
    private static func hunkStarts(_ header: String) throws -> (oldStart: Int, oldCount: Int, newStart: Int, newCount: Int) {
        let fields = header.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard fields.count >= 3, fields[1].hasPrefix("-"), fields[2].hasPrefix("+"),
              let old = side(fields[1].dropFirst()), let new = side(fields[2].dropFirst())
        else { throw DiffParseError.malformedHunkHeader(header) }
        return (old.start, old.count, new.start, new.count)
    }

    private static func side(_ text: Substring) -> (start: Int, count: Int)? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(parts[0]), start >= 0 else { return nil }
        if parts.count == 1 { return (start, 1) }
        guard parts.count == 2, let count = Int(parts[1]), count >= 0 else { return nil }
        return (start, count)
    }

    // MARK: - File headers

    private static func readHeaderLine(_ line: String, into file: inout FileDiff) {
        func value(after prefix: String) -> String? {
            line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
        }
        if let mode = value(after: "new file mode ") {
            file.status = .added; file.newMode = mode; file.oldPath = nil
        } else if let mode = value(after: "deleted file mode ") {
            file.status = .deleted; file.oldMode = mode; file.newPath = nil
        } else if let mode = value(after: "old mode ") {
            file.oldMode = mode
        } else if let mode = value(after: "new mode ") {
            file.newMode = mode
        } else if let percent = value(after: "similarity index ") {
            file.similarity = Int(percent.dropLast())
        } else if let path = value(after: "rename from ") {
            file.status = .renamed; file.oldPath = unquote(path)
        } else if let path = value(after: "rename to ") {
            file.status = .renamed; file.newPath = unquote(path)
        } else if let path = value(after: "copy from ") {
            file.status = .copied; file.oldPath = unquote(path)
        } else if let path = value(after: "copy to ") {
            file.status = .copied; file.newPath = unquote(path)
        } else if let path = value(after: "--- ") {
            file.oldPath = diffPath(path, prefix: "a/")
        } else if let path = value(after: "+++ ") {
            file.newPath = diffPath(path, prefix: "b/")
        } else if line == "GIT binary patch" || (line.hasPrefix("Binary files ") && line.hasSuffix(" differ")) {
            file.isBinary = true
        }
    }

    private static func finish(_ file: FileDiff) -> FileDiff {
        var file = file
        if file.status == .modified {
            if file.oldPath == nil, file.newPath != nil { file.status = .added }
            if file.newPath == nil, file.oldPath != nil { file.status = .deleted }
        }
        return file
    }

    /// A `---`/`+++` path: `/dev/null` is no file, and git appends a tab
    /// after names that contain a space.
    private static func diffPath(_ raw: String, prefix: String) -> String? {
        var path = raw
        if let tab = path.firstIndex(of: "\t") { path = String(path[..<tab]) }
        if path == "/dev/null" { return nil }
        path = unquote(path)
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// `a/<old> b/<new>` after `diff --git `. Both names are equal unless the
    /// file was renamed or copied, and then the extended headers name them
    /// anyway, so an ambiguous split only matters for display until then.
    private static func gitHeaderPaths(_ rest: Substring) -> (old: String, new: String)? {
        if rest.hasPrefix("\""), let close = closingQuote(in: rest) {
            let old = unquote(String(rest[...close]))
            let new = unquote(String(rest[rest.index(after: close)...].drop { $0 == " " }))
            return (strip(old, "a/"), strip(new, "b/"))
        }
        let half = (rest.count - 1) / 2
        let first = rest.prefix(half), second = rest.suffix(half)
        if rest.count % 2 == 1, first.dropFirst(2) == second.dropFirst(2), first.hasPrefix("a/"), second.hasPrefix("b/") {
            return (String(first.dropFirst(2)), String(second.dropFirst(2)))
        }
        guard let split = rest.range(of: " b/") else { return nil }
        return (strip(String(rest[..<split.lowerBound]), "a/"), String(rest[split.upperBound...]))
    }

    private static func strip(_ path: String, _ prefix: String) -> String {
        path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    private static func closingQuote(in text: Substring) -> Substring.Index? {
        var escaped = false
        for index in text.indices.dropFirst() {
            if escaped { escaped = false; continue }
            if text[index] == "\\" { escaped = true } else if text[index] == "\"" { return index }
        }
        return nil
    }

    /// Git quotes names with unusual bytes C-style (`"a/caf\303\251.txt"`).
    static func unquote(_ text: String) -> String {
        guard text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") else { return text }
        var bytes: [UInt8] = []
        var input = Array(text.utf8.dropFirst().dropLast())[...]
        while let byte = input.popFirst() {
            guard byte == UInt8(ascii: "\\"), let next = input.popFirst() else { bytes.append(byte); continue }
            switch next {
            case UInt8(ascii: "n"): bytes.append(0x0A)
            case UInt8(ascii: "t"): bytes.append(0x09)
            case UInt8(ascii: "r"): bytes.append(0x0D)
            case UInt8(ascii: "a"): bytes.append(0x07)
            case UInt8(ascii: "b"): bytes.append(0x08)
            case UInt8(ascii: "f"): bytes.append(0x0C)
            case UInt8(ascii: "v"): bytes.append(0x0B)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var value = Int(next - UInt8(ascii: "0"))
                for _ in 0..<2 {
                    guard let digit = input.first, (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(digit) else { break }
                    value = value * 8 + Int(digit - UInt8(ascii: "0"))
                    input = input.dropFirst()
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
            default: bytes.append(next)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
