import Foundation
import Observation
import ViewerCore

/// State of one diff reader: which cards it shows, what each card reveals,
/// blame, the open review note and the scroll requests its view carries
/// out. It knows nothing about sessions or windows: asking, going to a
/// definition, opening a new window and selecting a note go out through the
/// callbacks, and the shell decides what they do.
@Observable @MainActor
final class DiffReaderModel {
    enum Mode: String, CaseIterable, Sendable {
        case byStep
        case byFile

        var title: String {
            switch self {
            case .byStep: "By step"
            case .byFile: "By file"
            }
        }
    }

    /// One file card. By step: an excerpt of a step, keyed `s<step>:<n>`. By
    /// file: a whole changed file, keyed `f:<path>`, as in the demo.
    struct Card: Identifiable, Hashable, Sendable {
        let id: String
        let path: String
        let excerpt: ResolvedExcerpt?
    }

    /// A row the view should bring into view, optionally flashing it. The
    /// token makes a repeated request for the same row distinct.
    struct ScrollTarget: Equatable, Sendable {
        let cardID: String
        let row: Int?
        let flash: Bool
        let token: Int
    }

    let document: PRReviewDocument
    var mode: Mode = .byStep {
        didSet { if mode != oldValue { requestBlames() } }
    }
    private(set) var stepID: Int
    var showBlame = false {
        didSet { if showBlame != oldValue { requestBlames() } }
    }
    /// The note shown inline below its row; the demo's `S.focusFinding`.
    private(set) var expandedNoteID: String?
    /// The review notes, which the shell's panel may change.
    var notes: ReviewNotes
    var fontSize: CGFloat = DiffReaderStyle.codeFontSize
    /// The clock for blame ages; tests fix it.
    var now: Date = .now
    private(set) var blames: [String: Blame] = [:]
    private(set) var blameErrors: [String: String] = [:]
    private(set) var wholeFile: Set<String> = []
    private(set) var collapsed: Set<String> = []
    private(set) var scrollTarget: ScrollTarget?
    /// Layer shown per description key (`s:<step>`, `f:<path>`): 1, 2 or 3.
    private var layerLevels: [String: Int] = [:]
    /// Revealed rows per card; a card without an entry shows its base set.
    private var revealed: [String: DiffVisibility] = [:]
    private var scrollToken = 0
    private let blameStore: BlameStore
    private var blameTasks: [String: Task<Void, Never>] = [:]

    // MARK: Callbacks

    /// ⌘> or a context-menu Ask: a chip for the session.
    var onAsk: ((Chip) -> Void)?
    /// Go to definition. Without a handler, the reader reveals a destination
    /// that the PR's own files declare.
    var onGoToDefinition: ((DiffDefinitionRequest) -> Void)?
    /// Open a definition or a file in a new code-only window.
    var onOpenInNewWindow: ((DiffCodeTarget) -> Void)?
    /// A note dot was clicked, or `focus(note:)` opened a note.
    var onNoteSelected: ((ReviewNote) -> Void)?
    /// Extra definition lookup for names the PR's own files do not declare,
    /// such as a SCIP index. Consulted after the document's declarations.
    var definitionLookup: ((String, DiffCodeTarget) -> DiffCodeTarget?)?

    init(document: PRReviewDocument, blameStore: BlameStore = BlameStore()) {
        self.document = document
        self.blameStore = blameStore
        notes = document.notes
        stepID = document.steps.first?.id ?? 0
    }

    // MARK: Steps

    var step: ResolvedStep? { document.step(stepID) }

    var stepPosition: (index: Int, count: Int)? {
        guard let index = document.steps.firstIndex(where: { $0.id == stepID }) else { return nil }
        return (index + 1, document.steps.count)
    }

    var nextStep: ResolvedStep? {
        guard let index = document.steps.firstIndex(where: { $0.id == stepID }),
              index + 1 < document.steps.count else { return nil }
        return document.steps[index + 1]
    }

    /// Shows a step in By step mode, scrolled to its top.
    func focus(step id: Int) {
        guard document.step(id) != nil else { return }
        stepID = id
        mode = .byStep
        requestBlames()
        requestScroll(cardID: nil, row: nil, flash: false)
    }

    // MARK: Cards

    var cards: [Card] {
        switch mode {
        case .byStep:
            guard let step else { return [] }
            return step.excerpts.enumerated().compactMap { index, excerpt in
                document.file(excerpt.path) == nil ? nil
                    : Card(id: "s\(step.id):\(index)", path: excerpt.path, excerpt: excerpt)
            }
        case .byFile:
            return document.filesInReadingOrder.map { Card(id: "f:\($0.path)", path: $0.path, excerpt: nil) }
        }
    }

    func visibility(for card: Card) -> DiffVisibility {
        if let visibility = revealed[card.id] { return visibility }
        let rows = document.file(card.path)?.diff.rows ?? []
        return DiffVisibility(rows: rows, mode: card.excerpt.map { .excerpt($0.lines) } ?? .diff)
    }

    func segments(for card: Card) -> [DiffSegment] {
        visibility(for: card).segments(wholeFile: wholeFile.contains(card.path))
    }

    func rows(for card: Card) -> DiffCardRows {
        let diff = document.file(card.path)?.diff
        return DiffCardRows(rows: diff?.rows ?? [], segments: segments(for: card), path: card.path, notes: notes,
                            expandedNoteID: expandedNoteID, blame: showBlame ? blames[card.path] : nil)
    }

    func isCollapsed(_ path: String) -> Bool { collapsed.contains(path) }

    func toggleCollapsed(_ path: String) {
        if collapsed.contains(path) { collapsed.remove(path) } else { collapsed.insert(path) }
    }

    func toggleWholeFile(_ path: String) {
        if wholeFile.contains(path) { wholeFile.remove(path) } else { wholeFile.insert(path) }
    }

    func showWholeFile(_ path: String) {
        wholeFile.insert(path)
        collapsed.remove(path)
    }

    func expand(_ expander: GapExpander, in card: Card) {
        var visibility = visibility(for: card)
        visibility.reveal(expander)
        revealed[card.id] = visibility
    }

    // MARK: Layered descriptions

    func layer(_ key: String) -> Int { layerLevels[key] ?? 1 }

    func setLayer(_ key: String, to level: Int) { layerLevels[key] = level }

    // MARK: Navigation

    /// Brings a head line into view and flashes it, as the demo's
    /// `goToLineInStep`: in place when the open step's excerpt holds the line,
    /// otherwise in the file's By file card with the rows around it revealed.
    func reveal(path: String, line: Int) {
        guard let file = document.file(path), let row = file.diff.rowIndex(forNewLine: line) else { return }
        if mode == .byStep, let card = cards.first(where: { $0.path == path && $0.excerpt?.lines.contains(line) == true }) {
            requestScroll(cardID: card.id, row: row, flash: true)
            return
        }
        mode = .byFile
        collapsed.remove(path)
        let card = Card(id: "f:\(path)", path: path, excerpt: nil)
        var visibility = visibility(for: card)
        visibility.revealAround(row: row)
        revealed[card.id] = visibility
        requestScroll(cardID: card.id, row: row, flash: true)
    }

    func reveal(_ target: DiffCodeTarget) {
        if let line = target.line { reveal(path: target.path, line: line) } else { revealFile(target.path) }
    }

    /// Shows a file's By file card at its top.
    func revealFile(_ path: String) {
        guard document.file(path) != nil else { return }
        mode = .byFile
        collapsed.remove(path)
        requestScroll(cardID: "f:\(path)", row: nil, flash: false)
    }

    func scrollTargetHandled(_ target: ScrollTarget) {
        if scrollTarget == target { scrollTarget = nil }
    }

    private func requestScroll(cardID: String?, row: Int?, flash: Bool) {
        scrollToken += 1
        scrollTarget = ScrollTarget(cardID: cardID ?? "", row: row, flash: flash, token: scrollToken)
    }

    // MARK: Review notes

    /// A gutter dot: opens the note below its row, or closes it if open.
    func toggleNote(_ id: String) {
        guard let note = notes[id] else { return }
        if expandedNoteID == id {
            expandedNoteID = nil
        } else {
            expandedNoteID = id
            onNoteSelected?(note)
        }
    }

    /// Opens a note below its row and brings the row into view, from the
    /// panel or a location link.
    func focus(note id: String) {
        guard let note = notes[id], note.side == .head else { return }
        expandedNoteID = id
        onNoteSelected?(note)
        if let card = cards.first(where: { card in
            guard card.path == note.path, !isCollapsed(card.path),
                  let row = document.file(card.path)?.diff.rowIndex(forNewLine: note.line) else { return false }
            return visibility(for: card).isVisible(row, wholeFile: wholeFile.contains(card.path))
        }), let row = document.file(note.path)?.diff.rowIndex(forNewLine: note.line) {
            requestScroll(cardID: card.id, row: row, flash: true)
        } else {
            reveal(path: note.path, line: note.line)
        }
    }

    func closeNote() { expandedNoteID = nil }

    // MARK: Blame

    private func requestBlames() {
        guard showBlame else { return }
        for path in Set(cards.map(\.path)) where blames[path] == nil && blameTasks[path] == nil {
            guard let file = document.file(path), file.diff.newPath != nil, file.headText != nil else { continue }
            let store = blameStore, head = document.head, repository = document.repository
            blameTasks[path] = Task { [weak self] in
                do {
                    let blame = try await store.blame(path: path, commit: head, repository: repository)
                    self?.blames[path] = blame
                } catch {
                    self?.blameErrors[path] = error.localizedDescription
                }
                self?.blameTasks[path] = nil
            }
        }
    }

    /// Waits for the blame of every card on screen; for tests and snapshots.
    func loadBlames() async {
        requestBlames()
        for task in blameTasks.values { await task.value }
    }

    func blameLabel(_ commit: BlameCommit) -> String { commit.gutterLabel(at: now) }

    // MARK: Asking

    var commit: String { document.head }

    /// A selection of head lines, labelled with the file name, the lines and
    /// the innermost declaration that holds the first line.
    func selectionChip(path: String, lines: ClosedRange<Int>?) -> Chip {
        let name = Self.fileName(path)
        guard let lines else {
            return Chip(kind: .selection, path: path, commit: commit, label: "\(name) · deleted lines")
        }
        let span = lines.count == 1 ? "\(lines.lowerBound)" : "\(lines.lowerBound)-\(lines.upperBound)"
        let symbol = document.file(path)?.enclosingDeclaration(line: lines.lowerBound)?.qualifiedName
        return Chip(kind: .selection, path: path, lines: lines, symbol: symbol, commit: commit,
                    label: "\(name):\(span) · \(symbol ?? "selection")")
    }

    func symbolChip(_ symbol: String, at origin: DiffCodeTarget) -> Chip {
        let place = definition(of: symbol, at: origin) ?? origin
        let location = place.line.map { "\(Self.fileName(place.path)):\($0)" } ?? Self.fileName(place.path)
        return Chip(kind: .symbol, path: place.path, lines: place.line.map { $0...$0 }, symbol: symbol, commit: commit,
                    label: "\(symbol) · \(location)")
    }

    func lineChip(path: String, line: Int) -> Chip {
        Chip(kind: .line, path: path, lines: line...line, commit: commit, label: "\(Self.fileName(path)):\(line)")
    }

    func fileChip(path: String) -> Chip {
        Chip(kind: .file, path: path, commit: commit, label: "file \(path)")
    }

    func stepChip(_ step: ResolvedStep) -> Chip {
        Chip(kind: .step, commit: commit, label: "step \(step.id) · \(step.step.title)")
    }

    func ask(_ chip: Chip) { onAsk?(chip) }

    // MARK: Definitions

    func definition(of symbol: String, at origin: DiffCodeTarget) -> DiffCodeTarget? {
        document.definition(of: symbol, preferredPath: origin.path) ?? definitionLookup?(symbol, origin)
    }

    func goToDefinition(_ request: DiffDefinitionRequest) {
        if let onGoToDefinition { onGoToDefinition(request); return }
        if let destination = request.destination { reveal(destination) }
    }

    func openInNewWindow(_ target: DiffCodeTarget) { onOpenInNewWindow?(target) }

    static func fileName(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}
