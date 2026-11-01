import Foundation
import Observation
import ViewerCore

/// A view change a session proposed with `focus_code_path`, shown with Apply / Undo.
struct ViewChange: Identifiable, Equatable, Sendable {
    let id = UUID()
    let reason: String
    let order: [Int]?
    let step: Int?
    var isApplied = false
    /// The order before Apply, restored by Undo.
    var previousOrder: [Int]?
    var previousMoved: Set<Int> = []
}

/// One entry of the Session tab.
struct SessionEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case user(text: String, chips: [Chip])
        case agent(text: String)
        case viewChange(UUID)
        case notice(String)
        case failure(String)
    }

    let id = UUID()
    var kind: Kind
}

/// A Claude Code session in a panel: the PR's main session, or a fork promoted from a secondary
/// window. The sidecar owns the conversation; this holds what the panel shows.
@Observable @MainActor
final class ViewerSession: Identifiable {
    enum Phase: Equatable, Sendable {
        /// No sidecar session yet; the first send opens one.
        case notStarted
        case opening
        case ready
        /// The closing turn is asking for memories.
        case closing
        /// Proposed memories wait for Done (or a new session, or a window close).
        case memories
        case closed
    }

    let id = UUID()
    let pr: Int
    /// The sidecar session this one forks, for a promoted secondary window.
    let forkOf: ViewerSession?
    var sidecarID: String?
    var resumedID: String?
    var phase: Phase = .notStarted
    var entries: [SessionEntry] = []
    var chips: [Chip] = []
    var draft = ""
    var isBusy = false
    var viewChanges: [ViewChange] = []
    var memories: [ProposedMemory] = []
    var costUSD: Double = 0
    var lastError: String?

    init(pr: Int, forkOf: ViewerSession? = nil) {
        self.pr = pr
        self.forkOf = forkOf
    }

    var title: String { forkOf == nil ? "PR #\(pr) session" : "PR #\(pr) session, forked" }

    /// "Claude Code session, resumed", "new", "forked", or "not started".
    var stateLabel: String {
        switch phase {
        case .notStarted: "Claude Code session, starts on your first question"
        case .opening: "Claude Code session, opening"
        case .closing: "Claude Code session, closing"
        case .memories, .closed: "Claude Code session, closed"
        case .ready:
            if forkOf != nil { "Claude Code session, forked" }
            else if resumedID != nil { "Claude Code session, resumed" }
            else { "Claude Code session, new" }
        }
    }

    func addChip(_ chip: Chip) {
        guard !chips.contains(chip) else { return }
        chips.append(chip)
    }

    func removeChip(at index: Int) {
        guard chips.indices.contains(index) else { return }
        chips.remove(at: index)
    }

    /// Appends streamed text to the agent entry of the turn in progress.
    func appendDelta(_ text: String) {
        if case .agent(let existing)? = entries.last?.kind {
            entries[entries.count - 1].kind = .agent(text: existing + text)
        } else {
            entries.append(SessionEntry(kind: .agent(text: text)))
        }
    }

    func viewChange(_ id: UUID) -> ViewChange? { viewChanges.first { $0.id == id } }
}
