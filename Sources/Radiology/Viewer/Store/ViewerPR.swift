import Foundation
import ViewerCore

/// The viewer's code-path step; Radiology has its own `CodePathStep` for pasted traces.
typealias PRStep = ViewerCore.CodePathStep

/// A subsystem page from `wordbase/systems/<name>.md`: the "In Marin" card's map and the focused
/// tree's root.
struct SystemPage: Sendable, Equatable {
    let name: String
    let layers: Layers?
    let members: [String]
    let diagram: Diagram?

    /// The first directory member, such as `lib/shellbox/`: the focused tree's root.
    var rootDirectory: String? { members.first { $0.hasSuffix("/") } }

    func covers(_ path: String) -> Bool {
        members.contains { $0.hasSuffix("/") ? path.hasPrefix($0) : path == $0 }
    }
}

/// A prepared PR opened from `wordbase/prs/<n>/`, with the changed files between its merge base
/// and head read from the Marin clone.
struct ViewerPR: Sendable {
    let number: Int
    let directory: URL
    let wordbase: PRWordbase
    let changes: [FileChange]
    let system: SystemPage?
    /// Every file at head under the subsystem's root, for the focused tree.
    let headFiles: [String]

    var header: PRHeader { wordbase.description.header }
    var title: String { header.title ?? "Pull request #\(number)" }
    var head: String { header.head }
    var base: String { header.mergeBase }
    var repoName: String { header.repo?.split(separator: "/").last.map(String.init) ?? "marin" }
    var changedPaths: [String] { changes.flatMap { [$0.path] + ($0.oldPath.map { [$0] } ?? []) } }
    var additions: Int { changes.compactMap(\.additions).reduce(0, +) }
    var deletions: Int { changes.compactMap(\.deletions).reduce(0, +) }

    func step(_ id: Int) -> PRStep? { wordbase.step(id: id) }
    func change(path: String) -> FileChange? { changes.first { $0.path == path || $0.oldPath == path } }

    /// "rjpower · 30 files · +4882 −388 · base 8a92f90 · head 01a8bb8".
    var metaLine: String {
        var parts: [String] = []
        if let author = header.author { parts.append(author) }
        parts.append("\(changes.count) \(changes.count == 1 ? "file" : "files")")
        parts.append("+\(additions) −\(deletions)")
        parts.append("base \(base.prefix(7))")
        parts.append("head \(head.prefix(7))")
        return parts.joined(separator: " · ")
    }

    /// "MERGED", "OPEN": the toolbar's state pill.
    var stateTitle: String { (header.state ?? "open").uppercased() }

    /// The step diagrams' count, for the preparation record.
    var stepDiagramCount: Int { wordbase.diagrams.steps.count }
}

/// Reads a prepared PR off the main actor: the wordbase files, the changed files and head tree
/// through Radiology's `ReviewRepository` (the same app-owned store, under the same cache
/// directory, that Radiology's own PR review uses), and the subsystem that covers the change.
actor ViewerPRLoader {
    private let paths: ViewerPaths
    private let repository: ReviewRepository

    init(paths: ViewerPaths, cacheDirectory: URL? = nil) throws {
        self.paths = paths
        repository = try ReviewRepository(attachedRoot: paths.marin,
                                          cacheDirectory: cacheDirectory ?? IndexCache.default.directory(for: paths.marin))
    }

    func load(_ number: Int) async throws -> ViewerPR {
        let directory = paths.prDirectory(number)
        let wordbase: PRWordbase
        do {
            wordbase = try PRWordbase(directory: directory)
        } catch {
            throw BrowserError.message("Could not read wordbase/prs/\(number): \(error)")
        }
        let header = wordbase.description.header
        try await repository.fetch([header.head, header.mergeBase])
        let changes = try await repository.changes(base: header.mergeBase, head: header.head)
        let system = Self.system(covering: changes.map(\.path), in: paths.wordbase)
        var headFiles: [String] = []
        if let root = system?.rootDirectory {
            headFiles = try await repository.tree(of: header.head).map(\.path).filter { $0.hasPrefix(root) }.sorted()
        }
        return ViewerPR(number: number, directory: directory, wordbase: wordbase, changes: changes,
                        system: system, headFiles: headFiles)
    }

    /// A detached worktree of the head: the session's cwd and secondary windows' root.
    func worktree(head: String) async throws -> URL {
        try await repository.worktree(for: head)
    }

    /// The subsystem whose members cover the most changed paths.
    static func system(covering changed: [String], in wordbase: URL) -> SystemPage? {
        let directory = wordbase.appending(path: "systems", directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return nil }
        var best: (page: SystemPage, count: Int)?
        for case let url as URL in enumerator where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let entry = try? WordbaseEntry(markdown: text), entry.header.kind == .system else { continue }
            let name = entry.header.name ?? url.deletingPathExtension().lastPathComponent
            let page = SystemPage(name: name, layers: entry.header.layers, members: entry.header.members ?? [],
                                  diagram: entry.header.diagram)
            let count = changed.count { page.covers($0) }
            if count > 0, count > (best?.count ?? 0) { best = (page, count) }
        }
        return best?.page
    }
}
