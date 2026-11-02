import Foundation

/// One line of `notes.jsonl`.
public struct ReviewNote: Codable, Hashable, Sendable, Identifiable {
    public enum Side: String, Codable, Hashable, Sendable { case head, base }
    public enum Severity: String, Codable, Hashable, Sendable { case high, medium, low, design }
    public enum Status: String, Codable, Hashable, Sendable, CaseIterable {
        case draft, approved, rejected, posted, resolved
    }

    public var id: String
    public var path: String
    public var line: Int
    public var side: Side
    public var commit: String
    public var severity: Severity
    public var status: Status
    public var who: String
    public var l1: String
    public var l2: String
    public var githubCommentID: Int?
    public var created: String
    public var updated: String

    enum CodingKeys: String, CodingKey {
        case id, path, line, side, commit, severity, status, who, l1, l2
        case githubCommentID = "github_comment_id"
        case created, updated
    }

    public init(
        id: String, path: String, line: Int, side: Side = .head, commit: String, severity: Severity,
        status: Status = .draft, who: String, l1: String, l2: String, githubCommentID: Int? = nil,
        created: String, updated: String
    ) {
        self.id = id
        self.path = path
        self.line = line
        self.side = side
        self.commit = commit
        self.severity = severity
        self.status = status
        self.who = who
        self.l1 = l1
        self.l2 = l2
        self.githubCommentID = githubCommentID
        self.created = created
        self.updated = updated
    }

    /// Mark's own note: `who` is "you" or "you (…)", as in the demo's
    /// fixture. §6 has no field for this.
    public var isMine: Bool { who == "you" || who.hasPrefix("you (") }

    /// The gutter dot, or nil for a rejected note, which the demo hides.
    public var marker: Marker? {
        if status == .rejected { return nil }
        if status == .resolved { return .resolved }
        return isMine ? .mine : .draft
    }

    /// Amber for drafts and other sessions' notes, blue for Mark's own,
    /// grey once resolved.
    public enum Marker: Hashable, Sendable { case draft, mine, resolved }

    /// Whether the note sits on `row` of its file's diff.
    public func isOn(_ row: DiffRow) -> Bool {
        switch side {
        case .head: row.newLine == line
        case .base: row.kind == .deleted && row.oldLine == line
        }
    }

    /// The note as the confirm box and GitHub show it.
    public var postText: String { "\(path):\(line)\n\(l1)\n\n\(l2)" }
}

/// A button on a note card.
public enum ReviewAction: Hashable, Sendable, CaseIterable {
    case approve, reject, backToDraft

    public var title: String {
        switch self {
        case .approve: "Approve"
        case .reject: "Reject"
        case .backToDraft: "Back to draft"
        }
    }

    public var target: ReviewNote.Status {
        switch self {
        case .approve: .approved
        case .reject: .rejected
        case .backToDraft: .draft
        }
    }
}

extension ReviewNote.Status {
    /// The card's buttons, in the demo's order. Draft, approved and rejected
    /// notes offer the two other states; posted and resolved notes offer none.
    public var actions: [ReviewAction] {
        switch self {
        case .draft, .approved, .rejected: ReviewAction.allCases.filter { $0.target != self }
        case .posted, .resolved: []
        }
    }

    /// Every allowed move. Posting (approved to posted) happens only through
    /// `ReviewNotes.markPosted`, and resolving (posted to resolved) when an
    /// update turn sees the code change.
    public func canMove(to next: ReviewNote.Status) -> Bool {
        switch (self, next) {
        case (.approved, .posted), (.posted, .resolved): true
        default: actions.contains { $0.target == next }
        }
    }
}

public enum ReviewNoteError: Error, Equatable, Sendable {
    case unknownNote(String)
    case invalidTransition(id: String, from: ReviewNote.Status, to: ReviewNote.Status)
}

/// The notes of one PR, in file order, with the status changes the panel
/// makes and the "Post N approved" selection.
public struct ReviewNotes: Hashable, Sendable {
    public private(set) var notes: [ReviewNote]

    public init(notes: [ReviewNote]) { self.notes = notes }

    /// Parses `notes.jsonl`; blank lines are skipped.
    public init(jsonl: String) throws {
        let decoder = JSONDecoder()
        var notes: [ReviewNote] = []
        for (offset, line) in jsonl.normalizingLineEndings.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            do {
                notes.append(try decoder.decode(ReviewNote.self, from: Data(line.utf8)))
            } catch {
                throw WordbaseError.badNoteLine(offset + 1, String(describing: error))
            }
        }
        self.notes = notes
    }

    /// One JSON object per line, keys sorted, with a trailing newline.
    public func jsonl() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try notes.map { String(decoding: try encoder.encode($0), as: UTF8.self) + "\n" }.joined()
    }

    public subscript(id: String) -> ReviewNote? { notes.first { $0.id == id } }

    /// What "Post N approved notes" posts, in file order.
    public var approved: [ReviewNote] { notes.filter { $0.status == .approved } }
    public var draftCount: Int { notes.count { $0.status == .draft } }

    /// "Post 2 approved notes to GitHub".
    public var postButtonTitle: String {
        "Post \(approved.count) approved note\(approved.count == 1 ? "" : "s") to GitHub"
    }

    /// "1 draft waiting for a decision".
    public var draftHint: String { "\(draftCount) draft\(draftCount == 1 ? "" : "s") waiting for a decision" }

    /// The exact text the confirm box shows for the approved notes.
    public var postConfirmationText: String { approved.map(\.postText).joined(separator: "\n\n---\n\n") }

    /// The note whose dot a row shows: the first on that line that is not rejected.
    public func gutterNote(path: String, row: DiffRow) -> ReviewNote? {
        notes.first { $0.path == path && $0.status != .rejected && $0.isOn(row) }
    }

    public mutating func apply(_ action: ReviewAction, to id: String, at date: Date = .now) throws {
        try move(id, to: action.target, at: date)
    }

    /// Records a posted review: every note named in `commentIDs` moves from
    /// approved to posted with its GitHub comment id. Checks all ids before
    /// changing any note.
    public mutating func markPosted(_ commentIDs: [String: Int], at date: Date = .now) throws {
        for id in commentIDs.keys { try check(id, to: .posted) }
        for (id, comment) in commentIDs {
            try move(id, to: .posted, at: date)
            notes[notes.firstIndex { $0.id == id }!].githubCommentID = comment
        }
    }

    public mutating func resolve(_ id: String, at date: Date = .now) throws {
        try move(id, to: .resolved, at: date)
    }

    private func check(_ id: String, to status: ReviewNote.Status) throws {
        guard let note = self[id] else { throw ReviewNoteError.unknownNote(id) }
        guard note.status.canMove(to: status) else {
            throw ReviewNoteError.invalidTransition(id: id, from: note.status, to: status)
        }
    }

    private mutating func move(_ id: String, to status: ReviewNote.Status, at date: Date) throws {
        try check(id, to: status)
        let index = notes.firstIndex { $0.id == id }!
        notes[index].status = status
        notes[index].updated = date.formatted(.iso8601)
    }
}
