import Foundation
import ViewerCore

/// The main view's two orders (DESIGN.md §2): one step's excerpts, or every changed file.
enum ViewerMode: String, Sendable, CaseIterable, Identifiable {
    case byStep = "By step"
    case byFile = "By file"
    var id: Self { self }
}

/// A request for the main view to scroll to code. `revision` grows with every request, so the
/// reader can react to a repeated reveal of the same place.
struct RevealRequest: Equatable, Sendable {
    let path: String
    let line: Int?
    let function: String?
    /// True when the current step's excerpts hold the location, so the main view stays by step.
    let inStep: Bool
    let revision: Int
}

/// Which steps a session's reorder moved: the steps outside the longest run that kept its
/// relative order. Moving step 6 to the top of 1…8 moves only step 6.
enum StepOrdering {
    static func moved(original: [Int], reordered: [Int]) -> Set<Int> {
        let rank = Dictionary(uniqueKeysWithValues: original.enumerated().map { ($1, $0) })
        let ranks = reordered.map { rank[$0] ?? Int.max }
        guard !ranks.isEmpty else { return [] }
        // Longest increasing subsequence, quadratic: code paths have about ten steps.
        var length = Array(repeating: 1, count: ranks.count)
        var previous = Array(repeating: -1, count: ranks.count)
        for i in ranks.indices {
            for j in 0..<i where ranks[j] < ranks[i] && length[j] + 1 > length[i] {
                length[i] = length[j] + 1
                previous[i] = j
            }
        }
        var index = length.indices.max { length[$0] < length[$1] }!
        var kept = Set<Int>()
        while index >= 0 {
            kept.insert(reordered[index])
            index = previous[index]
        }
        return Set(reordered).subtracting(kept)
    }

    /// `order` restricted to known steps, with any step it leaves out appended in original order.
    static func normalized(_ order: [Int], steps: [Int]) -> [Int] {
        var seen = Set<Int>()
        let known = order.filter { steps.contains($0) && seen.insert($0).inserted }
        return known + steps.filter { !seen.contains($0) }
    }
}

extension PRStep {
    /// Whether one of this step's excerpts shows `path` at `line`, or holds `function`.
    func covers(path: String, line: Int?, function: String?) -> Bool {
        excerpts.contains { excerpt in
            guard excerpt.path == path else { return false }
            if let function, excerpt.functions.contains(function) { return true }
            if let line, let range = excerpt.lineRange { return range.contains(line) }
            return line == nil && function == nil
        }
    }

    /// The fallback line of `function` from the excerpt that names it first.
    func fallbackLine(path: String, function: String) -> Int? {
        excerpts.first { $0.path == path && $0.functions.first == function }?.lineRange?.lowerBound
    }
}

/// How a box in the "In Marin" map is drawn.
enum SystemNodeMark: Equatable, Sendable {
    /// The subsystem the PR is in.
    case here
    /// The PR changes one of the box's paths.
    case touched
    /// The box names paths and the PR changes none of them.
    case dimmed
    case plain

    /// A box in PR review: the PR's subsystem is here, and the PR touches or misses the rest. A
    /// box that stands for several packages (`systems:`) is here when one of them is the PR's
    /// subsystem, and touched when the PR changes any of them.
    static func mark(_ node: DiagramNode, system: String?, changed: [String]) -> SystemNodeMark {
        if let system, node.standsFor(system: system) { return .here }
        guard let touched = node.isTouched(byChangedPaths: changed) else { return .plain }
        return touched ? .touched : .dimmed
    }

    static func mark(id: String, paths: [String]?, system: String?, changed: [String]) -> SystemNodeMark {
        if let system, id.caseInsensitiveCompare(system) == .orderedSame { return .here }
        guard let paths, !paths.isEmpty else { return .plain }
        let touched = changed.contains { path in paths.contains { $0.hasSuffix("/") ? path.hasPrefix($0) : path == $0 } }
        return touched ? .touched : .dimmed
    }

    /// A box while reading a subsystem's page outside PR review: the box that holds the open
    /// file is here, by its most specific path, else the subsystem's own box. Nothing is dimmed,
    /// since there is no change to miss.
    static func readingMarks(_ nodes: [DiagramNode], system: String, openPath: String?) -> [String: SystemNodeMark] {
        var marks: [String: SystemNodeMark] = [:]
        if let openPath {
            let best = nodes.compactMap { node -> (id: String, length: Int)? in
                let lengths = node.coveredPaths.filter { $0.hasSuffix("/") ? openPath.hasPrefix($0) : openPath == $0 }.map(\.count)
                return lengths.max().map { (node.id, $0) }
            }.max { $0.length < $1.length }
            if let best { marks[best.id] = .here }
        }
        if marks.isEmpty, let own = nodes.first(where: { $0.standsFor(system: system) }) { marks[own.id] = .here }
        return marks
    }
}

/// Short labels for paths inside the subsystem's package: `lib/shellbox/src/shellbox/task.py`
/// reads `task.py`, as in the demo. Paths elsewhere keep their full form.
struct PathShortener: Sendable, Equatable {
    let prefix: String?

    init(system: SystemPage?) {
        if let system, let root = system.rootDirectory {
            prefix = "\(root)src/\(system.name)/"
        } else {
            prefix = nil
        }
    }

    func short(_ path: String) -> String {
        if let prefix, path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        return path
    }
}

/// The chips ⌘> and the context menus attach (DESIGN.md §2), with the demo's labels.
enum ChipFactory {
    static func file(_ path: String, commit: String, shortener: PathShortener) -> Chip {
        Chip(kind: .file, path: path, commit: commit, label: "file \(shortener.short(path))")
    }

    static func step(_ step: PRStep, commit: String) -> Chip {
        Chip(kind: .step, commit: commit, label: "step \(step.id) · \(step.title)")
    }

    static func box(_ node: DiagramNode, commit: String, shortener: PathShortener, line: Int? = nil) -> Chip {
        box(label: node.label, at: node.at, commit: commit, shortener: shortener, line: line)
    }

    static func box(label: String, at: CodeLocation?, commit: String, shortener: PathShortener, line: Int? = nil) -> Chip {
        guard let at else { return Chip(kind: .box, commit: commit, label: "component \(label)") }
        let location = line.map { "\(shortener.short(at.path)):\($0)" } ?? shortener.short(at.path)
        return Chip(kind: .box, path: at.path, lines: line.map { $0...$0 }, symbol: at.function, commit: commit,
                    label: "\(label) · \(location)")
    }

    static func note(_ note: ReviewNote, shortener: PathShortener) -> Chip {
        Chip(kind: .note, path: note.path, lines: note.line...note.line, commit: note.commit,
             label: "note \(shortener.short(note.path)):\(note.line)")
    }

    /// A code location in a reader: a symbol's lines, or one line.
    static func code(path: String, lines: ClosedRange<Int>, symbol: String?, commit: String, shortener: PathShortener) -> Chip {
        let range = lines.count > 1 ? "\(lines.lowerBound)-\(lines.upperBound)" : "\(lines.lowerBound)"
        let location = "\(shortener.short(path)):\(range)"
        if let symbol {
            return Chip(kind: .symbol, path: path, lines: lines, symbol: symbol, commit: commit, label: "\(location) · \(symbol)")
        }
        return Chip(kind: lines.count > 1 ? .selection : .line, path: path, lines: lines, commit: commit, label: location)
    }
}

/// What a diagram box's context menu offers, in order.
enum DiagramBoxAction: Hashable {
    case ask
    case openCode(CodeLocation)
    case openCodeInNewWindow(path: String)
    case goToStep(Int)
    case openStepDiagram(Int)

    func title(label: String) -> String {
        switch self {
        case .ask: "Ask About \(label)"
        case .openCode: "Open Its Code"
        case .openCodeInNewWindow: "Open Its Code in New Window"
        case .goToStep(let step): "Go to Step \(step)"
        case .openStepDiagram: "Open Step Diagram"
        }
    }

    /// Only the PR map offers a step's own diagram; inside a step diagram the box is already there.
    static func actions(for node: DiagramLayoutResult.Node, in key: DiagramKey, hasStepDiagram: (Int) -> Bool) -> [Self] {
        var actions: [Self] = [.ask]
        if let at = node.at { actions += [.openCode(at), .openCodeInNewWindow(path: at.path)] }
        if let step = node.step {
            actions.append(.goToStep(step))
            if key == .pr, hasStepDiagram(step) { actions.append(.openStepDiagram(step)) }
        }
        return actions
    }
}
