import AppKit
import Foundation
import Testing
import ViewerCore
@testable import Radiology

/// The card row model and the reader model, on synthetic rows and on #10640.
@MainActor
struct DiffCardRowsTests {
    static func rows(_ spec: String) -> [DiffRow] {
        var old = 1, new = 1
        return spec.map { tag in
            switch tag {
            case "d": defer { old += 1 }; return DiffRow(kind: .deleted, oldLine: old, newLine: nil, text: "old \(old)")
            case "a": defer { new += 1 }; return DiffRow(kind: .added, oldLine: nil, newLine: new, text: "new \(new)")
            default: defer { old += 1; new += 1 }; return DiffRow(kind: .context, oldLine: old, newLine: new, text: "line \(new)")
            }
        }
    }

    static func note(_ id: String, line: Int, status: ReviewNote.Status = .draft, who: String = "review session") -> ReviewNote {
        ReviewNote(id: id, path: "a.py", line: line, commit: "head", severity: .low, status: status, who: who,
                   l1: "Note \(id)", l2: "", created: "", updated: "")
    }

    @Test func linesFollowSegmentsAndOpenNotesSitBelowTheirRow() {
        let rows = Self.rows(String(repeating: "c", count: 20) + "da" + String(repeating: "c", count: 20))
        let notes = ReviewNotes(notes: [Self.note("n1", line: 21), Self.note("n2", line: 2), Self.note("n3", line: 22, status: .rejected)])
        let segments = DiffVisibility(rows: rows).segments()
        let closed = DiffCardRows(rows: rows, segments: segments, path: "a.py", notes: notes, expandedNoteID: nil, blame: nil)
        // gap, rows 17...24, gap
        #expect(closed.lines.first == .gap(DiffGap(rows: 0..<17, rowCount: 42)))
        #expect(closed.lines.count == 1 + 8 + 1)
        #expect(closed.dots.keys.sorted() == [21])
        #expect(closed.dots[21]?.id == "n1")
        // Row 1 (new line 2) is hidden, so n2 has no dot; n3 is rejected.
        let open = DiffCardRows(rows: rows, segments: segments, path: "a.py", notes: notes, expandedNoteID: "n1", blame: nil)
        let index = try! #require(open.lineIndex(ofRow: 21))
        #expect(open.lines[index + 1] == .note(notes["n1"]!))
        #expect(open.lines.count == closed.lines.count + 1)
    }

    @Test func blameLabelsTheFirstRowOfEachRunAfterEveryGap() {
        let rows = Self.rows("cccccccccacccccccccc")
        let shas = (1...20).map { $0 <= 12 ? String(repeating: "a", count: 40) : String(repeating: "b", count: 40) }
        let commits = [String(repeating: "a", count: 40): BlameCommit(sha: String(repeating: "a", count: 40), author: "Russell Power", time: 0, summary: "One"),
                       String(repeating: "b", count: 40): BlameCommit(sha: String(repeating: "b", count: 40), author: "Ada L", time: 0, summary: "Two")]
        let blame = Blame(lineSHAs: shas, commits: commits)
        let cardRows = DiffCardRows(rows: rows, segments: DiffVisibility(rows: rows).segments(), path: "a.py",
                                    notes: ReviewNotes(notes: []), expandedNoteID: nil, blame: blame)
        // Visible rows 6...12; the run changes at new line 13 (row 12).
        #expect(cardRows.blameLabels.keys.sorted() == [6, 12])
        #expect(cardRows.blameLabels[12]?.firstName == "Ada")
    }

    @Test func noteTextWrapsToItsCard() {
        let note = Self.note("n", line: 1)
        let narrow = DiffNoteText.cardHeight(ReviewNote(id: "x", path: "a", line: 1, commit: "c", severity: .low, who: "w",
                                                        l1: String(repeating: "word ", count: 80), l2: "", created: "", updated: ""), width: 300)
        #expect(narrow > DiffNoteText.cardHeight(note, width: 300))
        let layout = DiffCardLayout(lines: [.code(0), .gap(DiffGap(rows: 1..<5, rowCount: 5)), .note(note)], fontSize: 12,
                                    availableWidth: 900, gutterWidth: DiffReaderStyle.gutterWidth(blame: false))
        #expect(layout.tops == [0, 19, 19 + DiffReaderStyle.gapHeight])
        #expect(layout.line(atY: 25) == 1 && layout.line(atY: 5) == 0 && layout.line(atY: 10_000) == 2)
    }

    @Test func identifiersAroundAColumn() {
        let text = "    await finish_owned(own_cleanup(x))" as NSString
        #expect(DiffCodeTextView.identifier(in: text, at: 12) == "finish_owned")
        #expect(DiffCodeTextView.identifier(in: text, at: 22) == "finish_owned")
        #expect(DiffCodeTextView.identifier(in: text, at: 2) == nil)
    }
}

@MainActor
@Suite(.enabled(if: ViewerFixture.isAvailable, "needs marin/ and wordbase/ beside the checkout"))
struct DiffReaderModelTests {
    static let http = ViewerFixture.shellbox + "http_service.py"

    @Test func byStepCardsAreTheStepExcerpts() async throws {
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        #expect(model.stepID == 1 && model.mode == .byStep)
        model.focus(step: 6)
        #expect(model.cards.map(\.id) == ["s6:0", "s6:1", "s6:2"])
        #expect(model.nextStep?.id == 7)
        // The first excerpt of step 6 hides the 124 added lines above `_pump`.
        let card = model.cards[0]
        guard case .gap(let top) = model.segments(for: card).first else { Issue.record("no top gap"); return }
        #expect(top.label == "124 hidden lines at the top, 124 changed")
        #expect(top.expanders.map(\.title) == ["Show 15 above", "Show all"])
        model.expand(top.expanders[0], in: card)
        guard case .gap(let smaller) = model.segments(for: card).first else { Issue.record("no top gap"); return }
        #expect(smaller.count == 109)
        model.toggleWholeFile(Self.http)
        #expect(model.segments(for: card) == [.rows(0..<223)])
    }

    @Test func revealInPlaceOrInTheFileCard() async throws {
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        model.focus(step: 6)
        model.reveal(path: Self.http, line: 133)
        #expect(model.mode == .byStep)
        #expect(model.scrollTarget?.cardID == "s6:0" && model.scrollTarget?.row == 132 && model.scrollTarget?.flash == true)
        // Line 20 is outside every excerpt of step 6: By file, revealed.
        model.reveal(path: Self.http, line: 20)
        #expect(model.mode == .byFile)
        #expect(model.scrollTarget?.cardID == "f:\(Self.http)" && model.scrollTarget?.row == 19)
        let card = try #require(model.cards.first { $0.path == Self.http })
        #expect(model.visibility(for: card).isVisible(13) && model.visibility(for: card).isVisible(33))
    }

    @Test func noteDotsOpenAndCloseInlineNotes() async throws {
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        var selected: [String] = []
        model.onNoteSelected = { selected.append($0.id) }
        model.focus(step: 6)
        let rows = model.rows(for: model.cards[0])
        #expect(rows.dots[132]?.id == "f1")
        model.toggleNote("f1")
        #expect(model.expandedNoteID == "f1" && selected == ["f1"])
        let open = model.rows(for: model.cards[0])
        let index = try #require(open.lineIndex(ofRow: 132))
        #expect(open.lines[index + 1] == .note(model.notes["f1"]!))
        model.toggleNote("f1")
        #expect(model.expandedNoteID == nil && selected == ["f1"])
        // From the panel: f5 on line 327 of the local machine is outside step 6.
        model.focus(note: "f5")
        #expect(model.mode == .byFile && model.expandedNoteID == "f5")
        // Dot colours: draft amber, Mark's posted note blue, resolved grey.
        #expect(DiffGutterView.color(of: model.notes["f1"]!) == DiffReaderStyle.note)
        #expect(DiffGutterView.color(of: model.notes["f3"]!) == DiffReaderStyle.accent)
        #expect(DiffGutterView.color(of: model.notes["f4"]!) == DiffReaderStyle.resolvedDot)
    }

    @Test func chipsCarryKindPathLinesAndHead() async throws {
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        var asked: [Chip] = []
        model.onAsk = { asked.append($0) }
        model.ask(model.selectionChip(path: Self.http, lines: 125...147))
        model.ask(model.symbolChip("_pump", at: DiffCodeTarget(path: Self.http, line: 200)))
        model.ask(model.lineChip(path: Self.http, line: 133))
        #expect(asked.map(\.kind) == [.selection, .symbol, .line])
        #expect(asked[0].label == "http_service.py:125-147 · _pump" && asked[0].lines == 125...147)
        #expect(asked[1].label == "_pump · http_service.py:125" && asked[1].symbol == "_pump")
        #expect(asked[2].label == "http_service.py:133")
        #expect(asked.allSatisfy { $0.commit == ViewerFixture.head && $0.path == Self.http })
    }

    @Test func goToDefinitionGoesOutOrRevealsInPlace() async throws {
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        model.focus(step: 6)
        let origin = DiffCodeTarget(path: Self.http, line: 200)
        let request = DiffDefinitionRequest(symbol: "_pump", origin: origin, destination: model.definition(of: "_pump", at: origin))
        // With nobody listening, the reader reveals the definition itself:
        // `_pump` is in step 6's first excerpt, so it stays in By step.
        model.goToDefinition(request)
        #expect(model.mode == .byStep && model.scrollTarget?.cardID == "s6:0" && model.scrollTarget?.row == 124)
        var sent: [DiffDefinitionRequest] = []
        var windows: [DiffCodeTarget] = []
        model.onGoToDefinition = { sent.append($0) }
        model.onOpenInNewWindow = { windows.append($0) }
        model.goToDefinition(request)
        model.openInNewWindow(try #require(request.destination))
        #expect(sent == [request] && windows.first?.line == 125)
    }

    @Test func blameLoadsForTheCardsOnScreen() async throws {
        let model = DiffReaderModel(document: try await ViewerFixture.document())
        model.now = ViewerFixture.demoNow
        model.focus(step: 6)
        model.showBlame = true
        await model.loadBlames()
        let rows = model.rows(for: model.cards[0])
        let first = try #require(rows.blameLabels[124])
        #expect(model.blameLabel(first).hasPrefix(first.shortSHA + " "))
        #expect(model.blameLabel(first).hasSuffix("d"))
    }
}
