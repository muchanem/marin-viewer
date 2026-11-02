import Foundation
import Testing
@testable import ViewerCore

struct ReviewNotesTests {
    static func note(_ id: String, _ status: ReviewNote.Status, who: String = "review session", line: Int = 133) -> ReviewNote {
        ReviewNote(id: id, path: "lib/shellbox/src/shellbox/http_service.py", line: line, commit: "01a8bb8",
                   severity: .medium, status: status, who: who, l1: "\(id) one.", l2: "\(id) two.",
                   created: "2026-10-30T00:00:00Z", updated: "2026-10-30T00:00:00Z")
    }

    /// The demo's note set: two drafts, one posted, two resolved.
    static var demo: ReviewNotes {
        ReviewNotes(notes: [
            note("f1", .draft), note("f2", .draft, line: 20), note("f3", .posted, who: "you", line: 5),
            note("f4", .resolved, who: "you (agent draft)"), note("f5", .resolved, who: "you (agent draft)"),
        ])
    }

    @Test func cardButtonsFollowTheDemo() {
        #expect(ReviewNote.Status.draft.actions == [.approve, .reject])
        #expect(ReviewNote.Status.approved.actions == [.reject, .backToDraft])
        #expect(ReviewNote.Status.rejected.actions == [.approve, .backToDraft])
        #expect(ReviewNote.Status.posted.actions.isEmpty && ReviewNote.Status.resolved.actions.isEmpty)
        #expect(ReviewNote.Status.draft.actions.map(\.title) == ["Approve", "Reject"])
        #expect(ReviewNote.Status.approved.canMove(to: .posted) && !ReviewNote.Status.draft.canMove(to: .posted))
        #expect(ReviewNote.Status.posted.canMove(to: .resolved) && !ReviewNote.Status.draft.canMove(to: .resolved))
        #expect(!ReviewNote.Status.resolved.canMove(to: .draft))
    }

    @Test func approveThenPostTheSelection() throws {
        var notes = Self.demo
        #expect(notes.postButtonTitle == "Post 0 approved notes to GitHub")
        #expect(notes.draftHint == "2 drafts waiting for a decision")
        let now = Date(timeIntervalSince1970: 1_793_491_200)
        try notes.apply(.approve, to: "f1", at: now)
        #expect(notes["f1"]?.status == .approved && notes["f1"]?.updated == "2026-11-01T00:00:00Z")
        #expect(notes.postButtonTitle == "Post 1 approved note to GitHub")
        #expect(notes.draftHint == "1 draft waiting for a decision")
        try notes.apply(.approve, to: "f2", at: now)
        #expect(notes.approved.map(\.id) == ["f1", "f2"])
        #expect(notes.postConfirmationText == """
        lib/shellbox/src/shellbox/http_service.py:133
        f1 one.

        f1 two.

        ---

        lib/shellbox/src/shellbox/http_service.py:20
        f2 one.

        f2 two.
        """)

        // Posting is all or nothing: f3 is already posted, so nothing moves.
        #expect(throws: ReviewNoteError.invalidTransition(id: "f3", from: .posted, to: .posted)) {
            try notes.markPosted(["f1": 1, "f3": 3], at: now)
        }
        #expect(notes["f1"]?.status == .approved)
        try notes.markPosted(["f1": 101, "f2": 102], at: now)
        #expect(notes["f1"]?.status == .posted && notes["f1"]?.githubCommentID == 101)
        #expect(notes.approved.isEmpty)
        try notes.resolve("f1", at: now)
        #expect(notes["f1"]?.status == .resolved)
        #expect(throws: ReviewNoteError.unknownNote("nope")) { try notes.resolve("nope") }
    }

    @Test func rejectAndBackToDraft() throws {
        var notes = Self.demo
        try notes.apply(.reject, to: "f1")
        #expect(notes["f1"]?.status == .rejected)
        try notes.apply(.backToDraft, to: "f1")
        #expect(notes["f1"]?.status == .draft)
        #expect(throws: ReviewNoteError.invalidTransition(id: "f3", from: .posted, to: .approved)) {
            try notes.apply(.approve, to: "f3")
        }
    }

    @Test func gutterDots() throws {
        var notes = Self.demo
        let row133 = DiffRow(kind: .added, oldLine: nil, newLine: 133, text: "")
        #expect(notes.gutterNote(path: "lib/shellbox/src/shellbox/http_service.py", row: row133)?.id == "f1")
        #expect(notes["f1"]?.marker == .draft)
        #expect(notes["f3"]?.marker == .mine)
        #expect(notes["f4"]?.marker == .resolved, "DESIGN.md: grey once resolved, even for Mark's own")
        try notes.apply(.reject, to: "f1")
        // A rejected note has no dot, so the next note on the line shows.
        #expect(notes.gutterNote(path: "lib/shellbox/src/shellbox/http_service.py", row: row133)?.id == "f4")
        #expect(notes["f1"]?.marker == nil)
        // A deleted row has no new line; head-side notes never sit on it.
        let deleted = DiffRow(kind: .deleted, oldLine: 133, newLine: nil, text: "")
        #expect(notes.gutterNote(path: "lib/shellbox/src/shellbox/http_service.py", row: deleted) == nil)
        var base = Self.note("b1", .draft)
        base.side = .base
        #expect(base.isOn(deleted) && !base.isOn(row133))
    }

    @Test func jsonlRoundTrip() throws {
        let notes = Self.demo
        let text = try notes.jsonl()
        #expect(text.split(separator: "\n").count == 5)
        #expect(!text.contains("github_comment_id"), "absent optional stays absent")
        #expect(try ReviewNotes(jsonl: text) == notes)
        #expect(try ReviewNotes(jsonl: text.replacingOccurrences(of: "\n", with: "\r\n") + "\n\n") == notes)
        #expect {
            try ReviewNotes(jsonl: text + "{\"id\": \"broken\"}\n")
        } throws: { error in
            if case WordbaseError.badNoteLine(6, _) = error { return true }
            return false
        }
    }
}
