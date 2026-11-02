import Foundation

/// A description in three layers: a sentence, a paragraph, several
/// paragraphs. The later two are optional and start collapsed.
public struct Layers: Codable, Hashable, Sendable {
    public var l1: String
    public var l2: String?
    public var l3: [String]?

    public init(l1: String, l2: String? = nil, l3: [String]? = nil) {
        self.l1 = l1
        self.l2 = l2
        self.l3 = l3
    }
}

public enum EntryKind: String, Codable, Hashable, Sendable {
    case file, system, pr, reviewer
}

/// Front matter of `wordbase/<repo path>.md`, `wordbase/systems/<name>.md`
/// and `wordbase/reviewer.md` (DESIGN.md §6). Fields a kind does not use
/// are nil.
public struct EntryHeader: Codable, Hashable, Sendable {
    public var kind: EntryKind
    /// File entries: the repo path.
    public var path: String?
    /// System entries: the subsystem name.
    public var name: String?
    /// The code this description describes.
    public var commit: String?
    public var updated: String?
    /// Model and run that wrote the layers.
    public var by: String?
    public var l1: String?
    public var l2: String?
    public var l3: [String]?
    /// File entries: the subsystem the file belongs to.
    public var system: String?
    /// System entries: paths and child systems.
    public var members: [String]?
    public var uses: [String]?
    public var usedBy: [String]?
    public var diagram: Diagram?
    /// Set to the commit that deleted the file.
    public var deleted: String?
    /// Style-lint failures that survived one rewrite.
    public var lint: [String]?

    enum CodingKeys: String, CodingKey {
        case kind, path, name, commit, updated, by, l1, l2, l3, system, members, uses
        case usedBy = "used_by"
        case diagram, deleted, lint
    }

    public var layers: Layers? { l1.map { Layers(l1: $0, l2: l2, l3: l3) } }
}

/// Front matter of `wordbase/prs/<n>/pr.md`.
public struct PRHeader: Codable, Hashable, Sendable {
    public var kind: EntryKind
    public var number: Int?
    public var repo: String?
    public var title: String?
    public var author: String?
    public var state: String?
    public var head: String
    public var base: String
    public var mergeBase: String
    public var preparedAt: String
    public var sessionID: String
    public var commit: String?
    public var updated: String?
    public var by: String?
    public var l1: String
    public var l2: String?
    public var l3: [String]?

    enum CodingKeys: String, CodingKey {
        case kind, number, repo, title, author, state, head, base
        case mergeBase = "merge_base"
        case preparedAt = "prepared_at"
        case sessionID = "session_id"
        case commit, updated, by, l1, l2, l3
    }

    public var layers: Layers { Layers(l1: l1, l2: l2, l3: l3) }
}

/// A `## ` section of an entry's body, with its markdown text.
public struct EntrySection: Codable, Hashable, Sendable {
    public var title: String
    public var text: String
}

/// One `### \`name\`` subsection under `## Symbols`.
public struct SymbolEntry: Codable, Hashable, Sendable {
    public var name: String
    public var layers: Layers
}

/// One bullet under `## Notes`:
/// `- 2026-11-01 · 01a8bb8 · session 3f2a… · text`. A bullet that does not
/// start with a date keeps all of its text in `text`.
public struct EntryNote: Codable, Hashable, Sendable {
    public var date: String?
    public var commit: String?
    public var session: String?
    public var text: String

    public init(date: String? = nil, commit: String? = nil, session: String? = nil, text: String) {
        self.date = date
        self.commit = commit
        self.session = session
        self.text = text
    }

    /// Parses the bullet's text without its leading `- `.
    public init(bullet: String) {
        let parts = bullet.components(separatedBy: " · ")
        let isDate = parts.first.map { $0.count == 10 && $0.allSatisfy { $0.isNumber || $0 == "-" } } ?? false
        guard parts.count >= 3, isDate else {
            self.init(text: bullet)
            return
        }
        var rest = parts.dropFirst(2)
        var session: String?
        if parts.count >= 4, let first = rest.first, first.hasPrefix("session ") {
            session = String(first.dropFirst("session ".count))
            rest = rest.dropFirst()
        }
        self.init(date: parts[0], commit: parts[1], session: session, text: rest.joined(separator: " · "))
    }
}

/// A wordbase markdown file: front matter, then `## ` sections. `Symbols`
/// and `Notes` are parsed; other sections (such as the reviewer entry's
/// `How you review`) stay as text and parse with `notes(inSection:)`.
public struct MarkdownEntry<Header: Codable & Sendable>: Sendable {
    public var header: Header
    public var sections: [EntrySection]
    public var symbols: [SymbolEntry]

    public init(markdown: String) throws {
        guard let parts = FrontMatter.split(markdown) else { throw WordbaseError.missingFrontMatter }
        header = try FrontMatter.parse(parts.yaml).decode(Header.self)
        sections = Self.sections(parts.body, marker: "## ")
        symbols = try sections.first { $0.title == "Symbols" }.map { section in
            try Self.sections(section.text, marker: "### ").map { symbol in
                let name = symbol.title.trimmingCharacters(in: CharacterSet(charactersIn: "` "))
                do {
                    return SymbolEntry(name: name, layers: try FrontMatter.parse(symbol.text).decode(Layers.self))
                } catch {
                    throw WordbaseError.badSymbol(name, String(describing: error))
                }
            }
        } ?? []
    }

    public var notes: [EntryNote] { notes(inSection: "Notes") }

    /// The bullets of one section. Indented lines continue the bullet above.
    public func notes(inSection title: String) -> [EntryNote] {
        guard let section = sections.first(where: { $0.title == title }) else { return [] }
        var bullets: [String] = []
        for line in section.text.normalizingLineEndings.split(separator: "\n") {
            if line.hasPrefix("- ") {
                bullets.append(String(line.dropFirst(2)))
            } else if !bullets.isEmpty, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                bullets[bullets.count - 1] += " " + line.trimmingCharacters(in: .whitespaces)
            }
        }
        return bullets.map(EntryNote.init(bullet:))
    }

    /// Splits text at lines starting with `marker`. Text before the first
    /// marker is dropped.
    private static func sections(_ text: String, marker: String) -> [EntrySection] {
        var sections: [EntrySection] = []
        var body: [Substring] = []
        func close() {
            guard !sections.isEmpty else { return }
            sections[sections.count - 1].text = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            body = []
        }
        for line in text.normalizingLineEndings.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(marker) {
                close()
                sections.append(EntrySection(title: line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces), text: ""))
            } else {
                body.append(line)
            }
        }
        close()
        return sections
    }
}

extension MarkdownEntry: Equatable where Header: Equatable {}
extension MarkdownEntry: Hashable where Header: Hashable {}

public typealias WordbaseEntry = MarkdownEntry<EntryHeader>
public typealias PRDescription = MarkdownEntry<PRHeader>

public enum WordbaseError: Error, Equatable, Sendable {
    case missingFrontMatter
    case badSymbol(String, String)
    /// A `notes.jsonl` line that did not decode, one-based.
    case badNoteLine(Int, String)
}
