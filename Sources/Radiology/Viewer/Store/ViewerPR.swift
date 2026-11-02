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
    /// The packages this one builds on, and the packages that build on it.
    var uses: [String] = []
    var usedBy: [String] = []
    /// When the page was written, as an ISO timestamp.
    var updated: String?

    /// The first directory member, such as `lib/shellbox/`: the focused tree's root.
    var rootDirectory: String? { members.first { $0.hasSuffix("/") } }

    func covers(_ path: String) -> Bool {
        members.contains { $0.hasSuffix("/") ? path.hasPrefix($0) : path == $0 }
    }

    /// The page at `url`, or nil when it is not a system entry.
    static func read(_ url: URL) -> SystemPage? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let entry = try? WordbaseEntry(markdown: text), entry.header.kind == .system else { return nil }
        let header = entry.header
        return SystemPage(name: header.name ?? url.deletingPathExtension().lastPathComponent, layers: header.layers,
                          members: header.members ?? [], diagram: header.diagram, uses: header.uses ?? [],
                          usedBy: header.usedBy ?? [], updated: header.updated)
    }

    /// Every page under `wordbase/systems/`, nested ones included.
    static func readAll(wordbase: URL) -> [SystemPage] {
        let directory = wordbase.appending(path: "systems", directoryHint: .isDirectory)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { ($0 as? URL).flatMap { $0.pathExtension == "md" ? read($0) : nil } }
            .sorted { $0.name < $1.name }
    }

    /// The page whose members cover `path` most specifically.
    static func covering(_ path: String, in pages: [SystemPage]) -> SystemPage? {
        pages.compactMap { page -> (SystemPage, Int)? in
            let lengths = page.members.filter { $0.hasSuffix("/") ? path.hasPrefix($0) : path == $0 }.map(\.count)
            return lengths.max().map { (page, $0) }
        }.max { $0.1 < $1.1 }?.0
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

    /// "MERGED", "OPEN".
    var stateTitle: String { (header.state ?? "open").uppercased() }

    /// The window subtitle: "marin · Merged · rjpower · 30 files · +4882 −388 · base 8a92f90 ·
    /// head 01a8bb8".
    var subtitle: String {
        [repoName, (header.state ?? "open").capitalized, metaLine].joined(separator: " · ")
    }

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
        var best: (page: SystemPage, count: Int)?
        for page in SystemPage.readAll(wordbase: wordbase) {
            let count = changed.count { page.covers($0) }
            if count > 0, count > (best?.count ?? 0) { best = (page, count) }
        }
        return best?.page
    }
}
