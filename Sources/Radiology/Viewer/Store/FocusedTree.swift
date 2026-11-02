import Foundation

/// The Files tab during PR review (DESIGN.md §2): the subsystem's folders that hold changes, with
/// changed files and their step badges first, unchanged files behind "+ N unchanged", unchanged
/// folders behind one count, tests collapsed, and changes outside the subsystem under "Elsewhere".
struct FocusedTree: Equatable, Sendable {
    struct FileRow: Equatable, Sendable {
        let path: String
        let name: String
        let steps: [Int]
        let additions: Int?
        let deletions: Int?
        let hasDraftNote: Bool
    }

    enum Row: Equatable, Sendable, Identifiable {
        case root(String)
        case directory(key: String, label: String, depth: Int, changedCount: Int, isOpen: Bool)
        case file(FileRow, depth: Int)
        /// "+ N unchanged", or "hide unchanged" while open.
        case unchangedToggle(key: String, depth: Int, count: Int, isOpen: Bool)
        case quietFile(path: String, name: String, depth: Int)
        case unchangedFolders(count: Int, names: [String])
        case elsewhere(changedCount: Int)
        case elsewhereFile(FileRow)

        var id: String {
            switch self {
            case .root(let path): "root:\(path)"
            case .directory(let key, _, _, _, _): key
            case .file(let row, _): "file:\(row.path)"
            case .unchangedToggle(let key, _, _, _): key
            case .quietFile(let path, _, _): "quiet:\(path)"
            case .unchangedFolders: "unchanged-folders"
            case .elsewhere: "elsewhere"
            case .elsewhereFile(let row): "else:\(row.path)"
            }
        }

        /// The repository path a row stands for, when it stands for a file.
        var filePath: String? {
            switch self {
            case .file(let row, _), .elsewhereFile(let row): row.path
            case .quietFile(let path, _, _): path
            default: nil
            }
        }
    }

    let rows: [Row]

    /// Folder keys are `t:<dir>` and unchanged lists `q:<dir>`. `toggled` holds the keys the
    /// reader flipped away from their default: tests and unchanged lists start closed, other
    /// folders open.
    static func defaultIsOpen(_ key: String) -> Bool {
        if key.hasPrefix("q:") { return false }
        let directory = String(key.dropFirst(2))
        return !TestPathClassifier.isTestPath(directory + "/x.py")
    }

    init(root: String, headFiles: [String], changes: [FileChange], stepsByPath: [String: [Int]],
         draftPaths: Set<String>, toggled: Set<String>) {
        func isOpen(_ key: String) -> Bool { Self.defaultIsOpen(key) != toggled.contains(key) }
        func row(_ change: FileChange, name: String) -> FileRow {
            FileRow(path: change.path, name: name, steps: stepsByPath[change.path] ?? [],
                    additions: change.additions, deletions: change.deletions, hasDraftNote: draftPaths.contains(change.path))
        }
        let changedByPath = Dictionary(changes.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var byDirectory: [String: Set<String>] = [:]
        for path in headFiles + changes.map(\.path) where path.hasPrefix(root) {
            let relative = String(path.dropFirst(root.count))
            let directory = (relative as NSString).deletingLastPathComponent
            byDirectory[directory, default: []].insert((relative as NSString).lastPathComponent)
        }
        let directories = byDirectory.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        var rows: [Row] = [.root(root)]
        var unchanged: [String] = []
        for directory in directories {
            let names = byDirectory[directory]!.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            let full = { (name: String) in root + (directory.isEmpty ? "" : directory + "/") + name }
            let changed = names.filter { changedByPath[full($0)] != nil }
            let quiet = names.filter { changedByPath[full($0)] == nil }
            guard !changed.isEmpty else {
                unchanged.append(directory)
                continue
            }
            let depth = min(directory.isEmpty ? 0 : directory.split(separator: "/").count, 2)
            let key = "t:\(directory)"
            let open = isOpen(key)
            rows.append(.directory(key: key, label: directory.isEmpty ? "." : directory, depth: depth,
                                   changedCount: changed.count, isOpen: open))
            guard open else { continue }
            for name in changed { rows.append(.file(row(changedByPath[full(name)]!, name: name), depth: depth)) }
            if !quiet.isEmpty {
                let quietKey = "q:\(directory)"
                let quietOpen = isOpen(quietKey)
                if quietOpen { for name in quiet { rows.append(.quietFile(path: full(name), name: name, depth: depth)) } }
                rows.append(.unchangedToggle(key: quietKey, depth: depth, count: quiet.count, isOpen: quietOpen))
            }
        }
        // Only folders outside every changed folder count: a parent of a changed folder is not
        // "unchanged" in the sense the reader cares about.
        let changedDirectories = Set(directories.filter { !unchanged.contains($0) })
        let leafUnchanged = unchanged.filter { directory in
            !changedDirectories.contains { $0.hasPrefix(directory + "/") || directory.isEmpty }
        }
        if !leafUnchanged.isEmpty {
            rows.append(.unchangedFolders(count: leafUnchanged.count, names: leafUnchanged))
        }
        let elsewhere = changes.filter { !$0.path.hasPrefix(root) }
        if !elsewhere.isEmpty {
            rows.append(.elsewhere(changedCount: elsewhere.count))
            for change in elsewhere { rows.append(.elsewhereFile(row(change, name: change.path))) }
        }
        self.rows = rows
    }
}
