import Foundation
import ViewerCore

/// One tree-sitter capture on one line of a file, in UTF-16 offsets within
/// that line. A line's spans are in painting order: later spans colour over
/// earlier ones, as Radiology's reader applies them.
struct LineHighlight: Hashable, Sendable {
    let range: NSRange
    let capture: String
}

/// A place in the PR's head, or the base side of a deleted line.
struct DiffCodeTarget: Hashable, Sendable {
    var path: String
    var line: Int?
    var symbol: String?

    init(path: String, line: Int? = nil, symbol: String? = nil) {
        self.path = path
        self.line = line
        self.symbol = symbol
    }
}

/// Go to definition from the reader: the identifier, where it was clicked,
/// and its declaration when the PR's own head files declare it once.
struct DiffDefinitionRequest: Hashable, Sendable {
    var symbol: String
    var origin: DiffCodeTarget
    var destination: DiffCodeTarget?
}

/// A declaration in a head file, from Radiology's tree-sitter `symbols`
/// query: the bare name, its dotted name inside enclosing declarations, and
/// its one-based line span.
struct DiffDeclaration: Hashable, Sendable {
    let name: String
    let qualifiedName: String
    let kind: String
    let lines: ClosedRange<Int>
    /// The line of the name token, where Go to Definition lands.
    let nameLine: Int
}

/// A changed file with everything the reader draws for it.
struct PRFileReview: Sendable, Identifiable {
    var id: String { diff.path }
    var path: String { diff.path }
    let diff: FileDiff
    /// The change description from `files.json`, or the file's wordbase entry.
    let description: Layers?
    /// Head file text, for Whole file mode and for name resolution. Nil for
    /// a deleted or binary file.
    let headText: String?
    let languageName: String?
    /// Highlights by head line (index 0 is line 1).
    let headHighlights: [[LineHighlight]]
    /// Highlights by base line, for deleted rows.
    let baseHighlights: [[LineHighlight]]
    let declarations: [DiffDeclaration]
    let isTest: Bool

    func highlights(for row: DiffRow) -> [LineHighlight] {
        if let line = row.newLine { return headHighlights.indices.contains(line - 1) ? headHighlights[line - 1] : [] }
        if let line = row.oldLine { return baseHighlights.indices.contains(line - 1) ? baseHighlights[line - 1] : [] }
        return []
    }

    /// The innermost declaration whose span holds `line`.
    func enclosingDeclaration(line: Int) -> DiffDeclaration? {
        declarations.filter { $0.lines.contains(line) }.min { $0.lines.count < $1.lines.count }
    }

    /// Source, then tests, then everything else (DESIGN.md §2, By file).
    var displayGroup: Int {
        if isTest { return 1 }
        return SourceLanguageRegistry.language(for: path) != nil ? 0 : 2
    }
}

/// A step excerpt resolved against the head: the new-side lines it spans
/// and how they were found.
struct ResolvedExcerpt: Hashable, Sendable {
    enum Source: Hashable, Sendable {
        /// Every name in `functions` resolved; the span is their union.
        case functions
        /// A whole-module excerpt, or names that did not resolve: `lines`.
        case lines
    }

    let excerpt: Excerpt
    let lines: ClosedRange<Int>
    let source: Source
    /// Why `functions` could not be used, when they were given.
    let problem: String?

    var path: String { excerpt.path }
}

struct ResolvedStep: Hashable, Sendable, Identifiable {
    let step: ViewerCore.CodePathStep
    let excerpts: [ResolvedExcerpt]
    var id: Int { step.id }
}

/// Everything the diff reader shows for one PR: the wordbase's steps,
/// notes and descriptions, joined with whole-file diffs, head text and
/// highlighting from the Marin clone. Built off the main actor by
/// `PRReviewLoader`.
struct PRReviewDocument: Sendable {
    let number: Int?
    let title: String?
    let base: String
    let head: String
    /// The Marin clone the diffs and blame come from.
    let repository: URL
    let description: Layers
    let files: [PRFileReview]
    let steps: [ResolvedStep]
    var notes: ReviewNotes

    func file(_ path: String) -> PRFileReview? { files.first { $0.path == path } }

    func step(_ id: Int) -> ResolvedStep? { steps.first { $0.id == id } }

    /// Changed files in By file order: source, then tests, then other
    /// paths, alphabetical within each group.
    var filesInReadingOrder: [PRFileReview] {
        files.sorted { ($0.displayGroup, $0.path) < ($1.displayGroup, $1.path) }
    }

    /// Where `name` is declared among the PR's head files: a unique match,
    /// or the one in `preferredPath` when several files declare it.
    func definition(of name: String, preferredPath: String?) -> DiffCodeTarget? {
        var found: [DiffCodeTarget] = []
        for file in files {
            for declaration in file.declarations where declaration.name == name || declaration.qualifiedName == name {
                found.append(DiffCodeTarget(path: file.path, line: declaration.nameLine, symbol: declaration.qualifiedName))
            }
        }
        if found.count == 1 { return found[0] }
        let local = found.filter { $0.path == preferredPath }
        return local.count == 1 ? local[0] : nil
    }
}
