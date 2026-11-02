import Foundation

/// One step of `code-path.json`.
public struct CodePathStep: Codable, Hashable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var l1: String
    public var l2: String?
    /// The PR map box this step belongs to.
    public var node: String?
    public var excerpts: [Excerpt]

    public var layers: Layers { Layers(l1: l1, l2: l2) }
}

/// A code excerpt of a step. `functions` names one or more consecutive
/// declarations, resolved by name against the head commit; the excerpt
/// spans their union. An empty list is a whole-module excerpt. `lines` is
/// the fallback, rewritten after each resolution.
public struct Excerpt: Codable, Hashable, Sendable {
    public var path: String
    public var functions: [String]
    /// `[first, last]`, one-based and inclusive.
    public var lines: [Int]?

    public init(path: String, functions: [String] = [], lines: [Int]? = nil) {
        self.path = path
        self.functions = functions
        self.lines = lines
    }

    public var isWholeModule: Bool { functions.isEmpty }

    /// `lines` as a range, or nil unless it holds two ascending numbers.
    public var lineRange: ClosedRange<Int>? {
        guard let lines, lines.count == 2, lines[0] <= lines[1] else { return nil }
        return lines[0]...lines[1]
    }
}

/// A path and declaration a diagram box opens.
public struct CodeLocation: Codable, Hashable, Sendable {
    public var path: String
    public var function: String?
}

/// Boxes, edges and groups, without coordinates; the sidecar lays them out
/// into a card of about 460×196 points.
public struct Diagram: Codable, Hashable, Sendable {
    /// Nil means `auto`.
    public var layout: DiagramLayout?
    public var nodes: [DiagramNode]
    public var edges: [DiagramEdge]
    public var groups: [DiagramGroup]

    public init(layout: DiagramLayout? = nil, nodes: [DiagramNode], edges: [DiagramEdge], groups: [DiagramGroup] = []) {
        self.layout = layout
        self.nodes = nodes
        self.edges = edges
        self.groups = groups
    }

    /// A diagram without groups may leave the key out.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try container.decodeIfPresent(DiagramLayout.self, forKey: .layout)
        nodes = try container.decode([DiagramNode].self, forKey: .nodes)
        edges = try container.decodeIfPresent([DiagramEdge].self, forKey: .edges) ?? []
        groups = try container.decodeIfPresent([DiagramGroup].self, forKey: .groups) ?? []
    }

    public func node(id: String) -> DiagramNode? { nodes.first { $0.id == id } }
}

/// How the sidecar places a diagram's boxes.
public struct DiagramLayout: Codable, Hashable, Sendable {
    public enum Mode: String, Codable, Hashable, Sendable {
        /// ELK's layered algorithm, wrapped to the card's aspect ratio.
        case auto
        /// Every node carries a `grid` cell, scaled to the card.
        case grid
    }

    public enum Direction: String, Codable, Hashable, Sendable {
        case right = "RIGHT"
        case down = "DOWN"
    }

    public var mode: Mode
    public var direction: Direction?

    public init(mode: Mode, direction: Direction? = nil) {
        self.mode = mode
        self.direction = direction
    }
}

/// A node's cell in a `grid` layout: integer column and row, and an
/// optional column span.
public struct GridCell: Codable, Hashable, Sendable {
    public var col: Int
    public var row: Int
    public var span: Int?

    public init(col: Int, row: Int, span: Int? = nil) {
        self.col = col
        self.row = row
        self.span = span
    }
}

public struct DiagramNode: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var sub: String
    /// The code-path step a click goes to.
    public var step: Int?
    /// The code a box in a step diagram opens.
    public var at: CodeLocation?
    /// The files the box stands for. The app marks the box touched when the
    /// PR changes one of them and dims it when the PR changes none.
    public var paths: [String]?
    /// Subsystem maps only: the packages one box stands for when it stands
    /// for several neighbours (DESIGN.md §6).
    public var systems: [String]?
    public var grid: GridCell?

    /// Whether the PR touches this box, or nil when it names no paths. A
    /// path ending in `/` covers everything under it. A package listed under
    /// `systems` counts with its `lib/<name>/`, so a box that stands for
    /// several packages is touched even when its `paths` leave one out.
    public func isTouched(byChangedPaths changed: some Collection<String>) -> Bool? {
        let covered = coveredPaths
        guard !covered.isEmpty else { return nil }
        return changed.contains { path in covered.contains { $0.hasSuffix("/") ? path.hasPrefix($0) : path == $0 } }
    }

    /// `paths` plus `lib/<name>/` for every package under `systems`.
    public var coveredPaths: [String] {
        var covered = paths ?? []
        for name in systems ?? [] where !covered.contains("lib/\(name)/") { covered.append("lib/\(name)/") }
        return covered
    }

    /// Whether this box is subsystem `name`'s own box: its id, or one of the
    /// packages it stands for.
    public func standsFor(system name: String) -> Bool {
        id.caseInsensitiveCompare(name) == .orderedSame
            || (systems ?? []).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// `[from, to]` or `[from, to, label]`.
public struct DiagramEdge: Codable, Hashable, Sendable {
    public var from: String
    public var to: String
    public var label: String?

    public init(from: String, to: String, label: String? = nil) {
        self.from = from
        self.to = to
        self.label = label
    }

    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        from = try container.decode(String.self)
        to = try container.decode(String.self)
        label = container.isAtEnd ? nil : try container.decodeNil() ? nil : try container.decode(String.self)
        guard container.isAtEnd else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "an edge has at most three fields")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(from)
        try container.encode(to)
        if let label { try container.encode(label) }
    }
}

public struct DiagramGroup: Codable, Hashable, Sendable {
    public var label: String
    public var members: [String]
}

/// `diagrams.json`: the PR map and the step diagrams, keyed by step id.
public struct PRDiagrams: Codable, Hashable, Sendable {
    public var pr: Diagram
    public var steps: [String: Diagram]

    public func diagram(forStep id: Int) -> Diagram? { steps[String(id)] }
}

/// Everything under `wordbase/prs/<n>/`.
public struct PRWordbase: Sendable {
    public var description: PRDescription
    public var codePath: [CodePathStep]
    public var diagrams: PRDiagrams
    public var notes: ReviewNotes
    /// `files.json`: the change description per changed path (the file-header text).
    public var files: [String: Layers]

    public init(description: PRDescription, codePath: [CodePathStep], diagrams: PRDiagrams, notes: ReviewNotes, files: [String: Layers]) {
        self.description = description
        self.codePath = codePath
        self.diagrams = diagrams
        self.notes = notes
        self.files = files
    }

    /// Reads the five files; a missing `notes.jsonl` means no notes yet.
    public init(directory: URL) throws {
        func read(_ name: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(name)) }
        let decoder = JSONDecoder()
        description = try PRDescription(markdown: String(decoding: try read("pr.md"), as: UTF8.self))
        codePath = try decoder.decode([CodePathStep].self, from: try read("code-path.json"))
        diagrams = try decoder.decode(PRDiagrams.self, from: try read("diagrams.json"))
        files = try decoder.decode([String: Layers].self, from: try read("files.json"))
        let notesURL = directory.appendingPathComponent("notes.jsonl")
        notes = FileManager.default.fileExists(atPath: notesURL.path)
            ? try ReviewNotes(jsonl: String(decoding: try Data(contentsOf: notesURL), as: UTF8.self))
            : ReviewNotes(notes: [])
    }

    public func step(id: Int) -> CodePathStep? { codePath.first { $0.id == id } }
}
