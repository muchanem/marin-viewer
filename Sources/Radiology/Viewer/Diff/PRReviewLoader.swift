import Foundation
import ViewerCore

/// Builds a `PRReviewDocument` from `wordbase/prs/<n>/` and the Marin clone.
///
/// Every step runs off the main actor: one `git diff -U<large>` over the
/// whole PR parsed with ViewerCore, `git show` for the head and base text of
/// each changed file, Radiology's `SyntaxWorker` for highlighting and
/// declarations, and the step excerpts resolved by name against the head.
/// The clone is only read; nothing is checked out.
actor PRReviewLoader {
    /// Context lines for the whole-file diff: larger than any file in Marin.
    static let wholeFileContext = 1_000_000

    private let commands = CommandRunner()
    private let syntax = SyntaxWorker()
    private let git: URL

    init(git: URL? = nil) {
        self.git = git ?? ToolLocator.executable("git") ?? URL(filePath: "/usr/bin/git")
    }

    /// - Parameters:
    ///   - prDirectory: `wordbase/prs/<n>/`.
    ///   - wordbaseRoot: the wordbase checkout, for file entries; by default
    ///     two levels above `prDirectory`.
    ///   - repository: the Marin clone holding both commits.
    func load(prDirectory: URL, wordbaseRoot: URL? = nil, repository: URL) async throws -> PRReviewDocument {
        let wordbase = try PRWordbase(directory: prDirectory)
        let root = wordbaseRoot ?? prDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let header = wordbase.description.header
        let base = header.base, head = header.head

        let diffData = try await commands.run(git, arguments: [
            "-c", "core.quotePath=true", "diff", "--no-color", "--no-ext-diff", "-M",
            "-U\(Self.wholeFileContext)", base, head, "--",
        ], directory: repository)
        let diffs = try DiffRows.parseFiles(String(decoding: diffData, as: UTF8.self))
        try Task.checkCancellation()

        let excerpts = Dictionary(grouping: wordbase.codePath.flatMap(\.excerpts), by: \.path)
        var files: [PRFileReview] = []
        var resolved: [Excerpt: ResolvedExcerpt] = [:]
        for diff in diffs {
            let (file, fileExcerpts) = try await review(
                diff, base: base, head: head, repository: repository,
                description: wordbase.files[diff.path] ?? Self.entryLayers(root: root, path: diff.path),
                excerpts: excerpts[diff.path] ?? [])
            files.append(file)
            resolved.merge(fileExcerpts) { first, _ in first }
            try Task.checkCancellation()
        }

        let steps = wordbase.codePath.map { step in
            ResolvedStep(step: step, excerpts: step.excerpts.map { excerpt in
                resolved[excerpt] ?? ResolvedExcerpt(
                    excerpt: excerpt, lines: excerpt.lineRange ?? 1...1, source: .lines,
                    problem: excerpt.isWholeModule ? nil : "\(excerpt.path) is not a changed text file at the head.")
            })
        }
        return PRReviewDocument(
            number: header.number, title: header.title, base: base, head: head, repository: repository,
            description: header.layers, files: files, steps: steps, notes: wordbase.notes)
    }

    // MARK: - Files

    private func review(
        _ diff: FileDiff, base: String, head: String, repository: URL, description: Layers?, excerpts: [Excerpt]
    ) async throws -> (PRFileReview, [Excerpt: ResolvedExcerpt]) {
        var resolved: [Excerpt: ResolvedExcerpt] = [:]
        var headText: String?
        var headHighlights: [[LineHighlight]] = []
        var baseHighlights: [[LineHighlight]] = []
        var declarations: [DiffDeclaration] = []
        var languageName: String?
        if !diff.isBinary, let path = diff.newPath, diff.status != .deleted {
            let data = try await commands.run(git, arguments: ["show", "\(head):\(path)"], directory: repository)
            if let buffer = try? SourceBuffer(path: path, data: data) {
                headText = buffer.text
                let headSnapshot = try await syntax.parse(buffer)
                if let snapshot = headSnapshot {
                    languageName = snapshot.languageName
                    headHighlights = Self.lineHighlights(snapshot, buffer: buffer)
                    declarations = Self.declarations(snapshot, buffer: buffer)
                }
                for excerpt in excerpts where resolved[excerpt] == nil {
                    resolved[excerpt] = Self.resolve(excerpt, buffer: buffer, syntax: headSnapshot)
                }
            }
        }
        if !diff.isBinary, diff.deletions > 0, let path = diff.oldPath {
            let data = try await commands.run(git, arguments: ["show", "\(base):\(path)"], directory: repository)
            if let buffer = try? SourceBuffer(path: path, data: data), let snapshot = try await syntax.parse(buffer) {
                baseHighlights = Self.lineHighlights(snapshot, buffer: buffer)
            }
        }
        let file = PRFileReview(
            diff: diff, description: description, headText: headText, languageName: languageName,
            headHighlights: headHighlights, baseHighlights: baseHighlights, declarations: declarations,
            isTest: TestPathClassifier.isTestPath(diff.path))
        return (file, resolved)
    }

    /// `wordbase/<path>.md`'s layers, used when `files.json` has no entry.
    static func entryLayers(root: URL, path: String) -> Layers? {
        let url = root.appending(path: path + ".md")
        guard let data = try? Data(contentsOf: url),
              let entry = try? WordbaseEntry(markdown: String(decoding: data, as: UTF8.self)) else { return nil }
        return entry.header.layers
    }

    // MARK: - Highlighting

    /// Splits the snapshot's byte-ranged captures into per-line UTF-16
    /// spans, keeping Radiology's painting order.
    static func lineHighlights(_ snapshot: SyntaxSnapshot, buffer: SourceBuffer) -> [[LineHighlight]] {
        var lines = Array(repeating: [LineHighlight](), count: buffer.lineCount)
        let count = buffer.data.count
        for highlight in snapshot.highlights where !highlight.byteRange.isEmpty {
            let lower = max(0, highlight.byteRange.lowerBound), upper = min(count, highlight.byteRange.upperBound)
            guard lower < upper else { continue }
            let first = buffer.line(atByte: lower), last = buffer.line(atByte: upper - 1)
            for line in first...last {
                let start = buffer.lineStarts[line - 1]
                let end = line < buffer.lineCount ? buffer.lineStarts[line] - 1 : count
                let from = max(lower, start), to = min(upper, end)
                guard from < to else { continue }
                let lineUTF16 = buffer.utf16LineStarts[line - 1]
                let location = buffer.utf16Offset(forByte: from) - lineUTF16
                let length = buffer.utf16Offset(forByte: to) - lineUTF16 - location
                guard length > 0 else { continue }
                lines[line - 1].append(LineHighlight(range: NSRange(location: location, length: length), capture: highlight.name))
            }
        }
        return lines
    }

    // MARK: - Declarations and excerpts

    static func declarations(_ snapshot: SyntaxSnapshot, buffer: SourceBuffer) -> [DiffDeclaration] {
        snapshot.symbols.map { symbol in
            let parents = snapshot.symbols.filter {
                $0.id != symbol.id && $0.byteRange.lowerBound <= symbol.byteRange.lowerBound
                    && symbol.byteRange.upperBound <= $0.byteRange.upperBound
            }.sorted { $0.byteRange.count > $1.byteRange.count }
            let first = Self.firstLine(of: symbol, in: buffer, languageID: snapshot.languageID)
            let last = buffer.line(atByte: max(symbol.byteRange.lowerBound, symbol.byteRange.upperBound - 1))
            return DiffDeclaration(
                name: symbol.name, qualifiedName: (parents.map(\.name) + [symbol.name]).joined(separator: "."),
                kind: symbol.kind, lines: first...max(first, last),
                nameLine: buffer.line(atByte: symbol.selectionByteRange.lowerBound))
        }
    }

    /// A Python declaration's first line, moved up over its decorators so an
    /// excerpt shows `@dataclass` with the class.
    private static func firstLine(of symbol: DocumentSymbol, in buffer: SourceBuffer, languageID: String) -> Int {
        var line = buffer.line(atByte: symbol.byteRange.lowerBound)
        guard languageID == "python" else { return line }
        let lines = buffer.text.split(separator: "\n", omittingEmptySubsequences: false)
        while line > 1, lines[line - 2].trimmingCharacters(in: .whitespaces).hasPrefix("@") { line -= 1 }
        return line
    }

    /// Resolves an excerpt's `functions` by name against the head with
    /// Radiology's `CodePathSymbolResolver` (bare, dotted or `::` names;
    /// ambiguity is an error) and spans the union of their declarations.
    /// Falls back to `lines` for a whole-module excerpt or a failed name.
    static func resolve(_ excerpt: Excerpt, buffer: SourceBuffer, syntax snapshot: SyntaxSnapshot?) -> ResolvedExcerpt {
        let fallback = excerpt.lineRange ?? 1...1
        guard !excerpt.functions.isEmpty else {
            return ResolvedExcerpt(excerpt: excerpt, lines: fallback, source: .lines, problem: nil)
        }
        var spans: [ClosedRange<Int>] = []
        for name in excerpt.functions {
            do {
                let positions = try CodePathSymbolResolver.destinations(name, in: buffer, syntax: snapshot)
                guard positions.count == 1,
                      let symbol = snapshot?.symbols.first(where: { $0.selectionByteRange.lowerBound == positions[0] })
                else { throw BrowserError.message("‘\(name)’ has no single declaration in \(excerpt.path).") }
                let first = Self.firstLine(of: symbol, in: buffer, languageID: snapshot?.languageID ?? "")
                let last = buffer.line(atByte: max(symbol.byteRange.lowerBound, symbol.byteRange.upperBound - 1))
                spans.append(first...max(first, last))
            } catch {
                return ResolvedExcerpt(excerpt: excerpt, lines: fallback, source: .lines, problem: error.localizedDescription)
            }
        }
        let lower = spans.map(\.lowerBound).min()!, upper = spans.map(\.upperBound).max()!
        return ResolvedExcerpt(excerpt: excerpt, lines: lower...upper, source: .functions, problem: nil)
    }
}
