import Foundation

/// One path touched by a pull request, from `git diff --raw -M` between the
/// merge base and the head, with counts from `--numstat`. Paths are
/// repository-relative; `oldPath` differs from `path` only for renames and
/// copies.
struct FileChange: Identifiable, Hashable, Sendable {
    enum Status: Hashable, Sendable {
        case added
        case modified
        case deleted
        case renamed(similarity: Int)
        case copied(similarity: Int)
        /// Type change (file ↔ symlink) or an unrecognized status letter.
        case other(String)

        var title: String {
            switch self {
            case .added: "Added"
            case .modified: "Modified"
            case .deleted: "Deleted"
            case .renamed(let similarity): similarity >= 100 ? "Renamed" : "Renamed and modified"
            case .copied: "Copied"
            case .other(let letter): "Changed (\(letter))"
            }
        }

        var systemImage: String {
            switch self {
            case .added: "plus.circle"
            case .modified: "pencil.circle"
            case .deleted: "minus.circle"
            case .renamed, .copied: "arrow.triangle.swap"
            case .other: "questionmark.circle"
            }
        }
    }

    /// The path in the head revision, or the old path for a deletion.
    let path: String
    /// The path in the merge base when it differs (renames, copies).
    let oldPath: String?
    let status: Status
    /// Blob ids on each side, "" when absent, so Before bytes can be read
    /// by object id without guessing a path.
    let beforeBlob: String
    let afterBlob: String
    /// Line counts from `--numstat`; nil for binary files.
    let additions: Int?
    let deletions: Int?

    var id: String { path }
    var isBinary: Bool { additions == nil }
    var existsBefore: Bool { status != .added }
    var existsAfter: Bool { status != .deleted }
    /// The path to read for a given revision, when that revision has one.
    func path(in revision: ReviewRevision) -> String? {
        switch revision {
        case .after: existsAfter ? path : nil
        case .before: existsBefore ? (oldPath ?? path) : nil
        }
    }
}

enum FileChangeParser {
    /// Parses `git diff --raw -M -z <base> <head>` output. Each record is
    /// `:<oldmode> <newmode> <oldsha> <newsha> <status>\0<path>\0` with a
    /// second path for R/C. The mode and sha fields are space-separated;
    /// the status letter may carry a similarity score (`R100`).
    static func parseRaw(_ data: Data) throws -> [FileChange] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var changes: [FileChange] = []
        var index = 0
        while index < fields.count {
            let header = fields[index]
            if header.isEmpty { index += 1; continue }
            guard header.hasPrefix(":") else { throw BrowserError.message("Unrecognized diff record: \(header)") }
            let parts = header.dropFirst().split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 5, index + 1 < fields.count else { throw BrowserError.message("Unrecognized diff record: \(header)") }
            let before = String(parts[2])
            let after = String(parts[3])
            let statusText = String(parts[4])
            let letter = statusText.prefix(1)
            let score = Int(statusText.dropFirst()) ?? 100
            let first = fields[index + 1]
            index += 2
            switch letter {
            case "A": changes.append(FileChange(path: first, oldPath: nil, status: .added, beforeBlob: before, afterBlob: after, additions: 0, deletions: 0))
            case "D": changes.append(FileChange(path: first, oldPath: nil, status: .deleted, beforeBlob: before, afterBlob: after, additions: 0, deletions: 0))
            case "M", "T":
                changes.append(FileChange(path: first, oldPath: nil, status: letter == "M" ? .modified : .other("T"), beforeBlob: before, afterBlob: after, additions: 0, deletions: 0))
            case "R", "C":
                guard index < fields.count else { throw BrowserError.message("Rename record without a destination: \(first)") }
                let second = fields[index]
                index += 1
                changes.append(FileChange(path: second, oldPath: first, status: letter == "R" ? .renamed(similarity: score) : .copied(similarity: score),
                                          beforeBlob: before, afterBlob: after, additions: 0, deletions: 0))
            default:
                changes.append(FileChange(path: first, oldPath: nil, status: .other(String(letter)), beforeBlob: before, afterBlob: after, additions: 0, deletions: 0))
            }
        }
        return changes
    }

    /// Merges `git diff --numstat -M -z` counts into parsed changes. Records
    /// are `<add>\t<del>\t<path>\0`; renames use `<add>\t<del>\t\0<old>\0<new>\0`.
    /// `-` counts mark binary files.
    static func applyNumstat(_ data: Data, to changes: [FileChange]) -> [FileChange] {
        let fields = data.split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var counts: [String: (Int?, Int?)] = [:]
        var index = 0
        while index < fields.count {
            let record = fields[index]
            index += 1
            guard !record.isEmpty else { continue }
            let columns = record.split(separator: "\t", omittingEmptySubsequences: false)
            guard columns.count == 3 else { continue }
            let additions = Int(columns[0])
            let deletions = Int(columns[1])
            var path = String(columns[2])
            if path.isEmpty, index + 1 < fields.count {
                // Rename: the next two fields are the old and new paths.
                path = fields[index + 1]
                index += 2
            }
            counts[path] = (additions, deletions)
        }
        return changes.map { change in
            guard let (additions, deletions) = counts[change.path] else { return change }
            return FileChange(path: change.path, oldPath: change.oldPath, status: change.status, beforeBlob: change.beforeBlob,
                              afterBlob: change.afterBlob, additions: additions, deletions: deletions)
        }
    }
}
