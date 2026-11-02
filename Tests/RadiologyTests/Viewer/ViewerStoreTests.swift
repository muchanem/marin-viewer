import Foundation
import Testing
import ViewerCore
@testable import Radiology

/// Saved `notes.jsonl` writes, captured instead of touching the fixture.
final class NoteWrites: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    var last: String? { lock.withLock { texts.last } }
    func record(_ text: String) { lock.withLock { texts.append(text) } }
}

@Suite(.serialized) @MainActor
struct ViewerStoreTests {
    /// A store on the fixture whose sidecar answers from `script`.
    private func store(_ fixture: ShellFixture, writes: NoteWrites = NoteWrites(),
                       script: @escaping @Sendable (JSONValue) -> [JSONValue] = ViewerStoreTests.sidecar) throws -> (ViewerStore, ScriptedTransport) {
        let transport = ScriptedTransport(script: script)
        let store = ViewerStore(paths: fixture.paths, sidecar: SidecarClient(makeTransport: { transport }),
                                writeNotes: { _, text in writes.record(text) })
        store.install(try fixture.loadPR())
        return (store, transport)
    }

    /// A sidecar that opens sessions, queues sends, closes with three memories and keeps notes.
    nonisolated static let sidecar: @Sendable (JSONValue) -> [JSONValue] = { message in
        let respond = { (result: JSONValue) in [ScriptedTransport.response(message, result)] }
        switch message["type"]?.string {
        case "session.open": return respond(["session": "s-1", "resumed": .null, "forked": false])
        case "session.send": return respond(["queued": true])
        case "session.close":
            let notes: JSONValue = [
                ["target": "wordbase/lib/shellbox/src/shellbox/http_service.py.md · notes", "text": "Limits.", "commit": "c"],
                ["target": "wordbase/systems/shellbox.md · notes", "text": "Throughput.", "commit": "c"],
                ["target": "wordbase/reviewer.md · how you review", "text": "Cancellation first.", "commit": "c"],
            ]
            return [["type": "notes.proposed", "session": "s-1", "notes": notes], ScriptedTransport.response(message, ["closed": true, "proposed": 3])]
        case "notes.keep": return respond(["files": ["wordbase/reviewer.md"], "commit": "abc"])
        case "review.post":
            let comments: [JSONValue] = (message["notes"]?.array ?? []).enumerated().map { index, note in
                ["note_id": note["id"] ?? .null, "github_comment_id": .number(Double(1000 + index))]
            }
            return respond(["review_id": 5, "comments": .array(comments), "recorded": true])
        case "layout": return respond(["mode": "grid"])
        default: return respond([:])
        }
    }

    @Test func openingAPRStartsByStepOnTheFirstStepWithThePanelOpen() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, _) = try store(fixture)
        #expect(store.isReviewing && store.mode == .byStep && store.focusedStepID == 1)
        #expect(store.stepOrder == [1, 2, 3] && store.notes.notes.count == 3)
        #expect(store.mainWindow.isPanelPresented && store.mainWindow.panelTab == .session)
        #expect(store.pr?.system?.name == "shellbox" && store.pr?.system?.rootDirectory == "lib/shellbox/")
        #expect(store.pr?.metaLine == "rjpower · 5 files · +758 −42 · base 8a92f90 · head 01a8bb8")
        #expect(store.mainSession?.title == "PR #10640 session")
    }

    @Test func footersCountWhatTheTabsShow() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, _) = try store(fixture)
        #expect(store.footer(for: .changes, searchMatches: 0) == "4 of 5 files · tests hidden")
        store.hidesTests = false
        #expect(store.visibleChanges.count == 5 && store.footer(for: .changes, searchMatches: 0) == "5 of 5 files")
        #expect(store.footer(for: .steps, searchMatches: 0) == "3 steps · prepared before your review")
        #expect(store.draftNotePaths == [ShellFixture.src + "http_service.py", ShellFixture.src + "task.py"])
    }

    @Test func stepDiagramsZoomAndTheirBoxesOpenCodeOrSayWhyNot() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, _) = try store(fixture)
        let window = store.mainWindow
        store.openStepDiagram(1, in: window)
        #expect(window.zoomedStep == nil && store.focusedStepID == 1)
        #expect(store.toast?.text == "Step 1 has no diagram of its own; its code is short enough to read directly.")

        store.openStepDiagram(2, in: window)
        #expect(window.zoomedStep == 2 && store.focusedStepID == 2 && store.mode == .byStep)
        let at = try ShellFixture.location(ShellFixture.src + "backends/local/machine.py", function: "LocalMachineFactory.create_task")
        store.openCode(of: .init(id: "ct", label: "create_task", at: at, x: 0, y: 0, w: 90, h: 34))
        #expect(store.mode == .byStep && store.revealRequest?.inStep == true && window.zoomedStep == 2)
        store.openCode(of: .init(id: "cl", label: "caller", x: 0, y: 0, w: 90, h: 34))
        #expect(store.toast?.text == "caller is outside this repository.")
        window.zoomOut()
        #expect(window.zoomedStep == nil)
    }

    @Test func revealStaysByStepInsideTheStepAndSwitchesByFileOutside() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, _) = try store(fixture)
        store.focus(step: 3)
        store.reveal(path: ShellFixture.src + "task.py", line: 140)
        #expect(store.mode == .byStep && store.revealRequest?.inStep == true && store.revealRequest?.line == 140)
        store.reveal(path: ShellFixture.src + "http_service.py", line: 133)
        #expect(store.mode == .byFile && store.revealRequest?.inStep == false)
        store.focus(step: 2)
        #expect(store.mode == .byStep && store.revealRequest == nil)
        store.reveal(path: ShellFixture.src + "backends/local/machine.py", function: "LocalMachineFactory.create_task")
        #expect(store.mode == .byStep && store.revealRequest?.line == 1029)
        #expect(store.step(after: 2)?.id == 3 && store.step(after: 3) == nil)
    }

    @Test func noteFocusOpensTheNotesTabAndTheLocationLinkOpensByFile() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, _) = try store(fixture)
        store.mainWindow.isPanelPresented = false
        store.focus(note: "f1")
        #expect(store.focusedNote?.id == "f1" && store.mainWindow.isPanelPresented && store.mainWindow.panelTab == .notes)
        store.focus(note: "f1")
        #expect(store.focusedNoteID == nil)
        store.revealNote("f2")
        #expect(store.focusedNoteID == "f2" && store.mode == .byFile && store.revealRequest?.line == 133)
    }

    @Test func approvingSavesAndPostingSendsOnlyTheApprovedNotes() async throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let writes = NoteWrites()
        let (store, transport) = try store(fixture, writes: writes)
        store.apply(.approve, to: "f1")
        #expect(store.notes["f1"]?.status == .approved && writes.last?.contains(#""status":"approved""#) == true)
        #expect(store.notes.postButtonTitle == "Post 1 approved note to GitHub")
        #expect(store.notes.postConfirmationText.hasPrefix(ShellFixture.src + "http_service.py:133\n"))
        await store.postApprovedNotes()
        let post = try #require(transport.sent(type: "review.post").first)
        #expect(post["pr"]?.int == 10640 && post["notes"]?.array?.count == 1 && post["notes"]?.array?.first?["id"]?.string == "f1")
        #expect(post["notes"]?.array?.first?["body"]?.string == "A retry can arrive while the host still counts 16.\n\nThe guest starts its timer first.")
        #expect(store.notes["f1"]?.status == .posted && store.notes["f1"]?.githubCommentID == 1000)
        #expect(store.toast?.text == "Posted 1 review note to #10640.")
        store.apply(.approve, to: "f3")
        #expect(store.notesError != nil && store.notes["f3"]?.status == .posted)
    }

    @Test func aChipOpensTheSessionAndTheFirstSendOpensItInTheWorktree() async throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, transport) = try store(fixture)
        let session = try #require(store.mainSession)
        store.mainWindow.isPanelPresented = false
        store.mainWindow.panelTab = .notes
        let step = try #require(store.pr?.step(3))
        store.ask(ChipFactory.step(step, commit: ShellFixture.head))
        #expect(session.chips.map(\.label) == ["step 3 · Wait for readiness"])
        #expect(store.mainWindow.isPanelPresented && store.mainWindow.panelTab == .session)
        store.ask(ChipFactory.step(step, commit: ShellFixture.head))
        #expect(session.chips.count == 1)
        session.draft = "What waits here?"
        await store.send(session)
        let open = try #require(transport.sent(type: "session.open").first)
        #expect(open["scope"]?["pr"]?.int == 10640 && open["resume"] == nil && open["cwd"]?.string == fixture.paths.marin.path)
        let send = try #require(transport.sent(type: "session.send").first)
        #expect(send["session"]?.string == "s-1" && send["text"]?.string == "What waits here?")
        #expect(send["chips"]?.array?.first?["label"]?.string == "step 3 · Wait for readiness")
        #expect(session.chips.isEmpty && session.draft.isEmpty && session.isBusy && session.phase == .ready)
        store.sidecarClient(store.sidecar, received: .delta(session: "s-1", text: "It waits "))
        store.sidecarClient(store.sidecar, received: .delta(session: "s-1", text: "on probes."))
        store.sidecarClient(store.sidecar, received: .turnResult(session: "s-1", costUSD: 0.1, isError: false, text: nil))
        #expect(session.entries.last?.kind == .agent(text: "It waits on probes.") && !session.isBusy && session.costUSD == 0.1)
    }

    @Test func aProposedReorderAppliesWithAMovedTagAndUndoes() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, _) = try store(fixture)
        let session = try #require(store.mainSession)
        session.sidecarID = "s-1"
        store.sidecarClient(store.sidecar, received: .uiCommand(session: "s-1", name: "focus_code_path",
                                                               args: ["order": [3, 1, 2], "reason": "The session moved step 3 to the top."]))
        let change = try #require(session.viewChanges.first)
        #expect(session.entries.last?.kind == .viewChange(change.id))
        store.applyViewChange(change.id, in: session)
        #expect(store.stepOrder == [3, 1, 2] && store.movedSteps == [3] && store.focusedStepID == 3)
        #expect(session.viewChange(change.id)?.isApplied == true)
        store.applyViewChange(change.id, in: session)
        #expect(store.stepOrder == [1, 2, 3] && store.movedSteps.isEmpty)
    }

    @Test func sessionCommandsOpenLocationsAndDraftNotes() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let writes = NoteWrites()
        let (store, _) = try store(fixture, writes: writes)
        store.handleUICommand("open_location", args: ["path": .string(ShellFixture.src + "http_service.py"), "line": 125], session: store.mainSession)
        #expect(store.mode == .byFile && store.revealRequest?.line == 125)
        store.handleUICommand("draft_review_note", args: ["path": .string(ShellFixture.src + "task.py"), "line": 10, "side": "head",
                                                         "severity": "high", "l1": "Leaks a task."], session: store.mainSession)
        let note = try #require(store.notes.notes.last)
        #expect(note.status == .draft && note.severity == .high && note.line == 10 && note.commit == ShellFixture.head)
        #expect(writes.last?.contains("Leaks a task.") == true)
    }

    @Test func closingProposesMemoriesAndDoneKeepsTheOnesLeft() async throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, transport) = try store(fixture)
        let session = try #require(store.mainSession)
        session.draft = "hi"
        await store.send(session)
        await store.closeSession(session)
        #expect(await eventually { session.memories.count == 3 })
        #expect(session.phase == .memories)
        store.dropMemory(session.memories[1], from: session)
        await store.keepMemories(session, reason: "added to the wordbase")
        let keep = try #require(transport.sent(type: "notes.keep").first)
        #expect(keep["session"]?.string == "s-1" && keep["notes"]?.array?.count == 2)
        #expect(store.toast?.text == "2 notes kept: added to the wordbase.")
        #expect(store.mainSession !== session && store.mainSession?.phase == .notStarted && session.phase == .closed)
    }

    @Test func aNewQuestionKeepsPendingMemoriesFirst() async throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, transport) = try store(fixture)
        let session = try #require(store.mainSession)
        session.draft = "hi"
        await store.send(session)
        await store.closeSession(session)
        #expect(await eventually { session.memories.count == 3 })
        store.ask(ChipFactory.file(ShellFixture.src + "task.py", commit: ShellFixture.head, shortener: store.shortener))
        #expect(await eventually { !transport.sent(type: "notes.keep").isEmpty })
        #expect(await eventually { store.toast?.text == "3 notes kept: a new question started." })
        #expect(await eventually { store.mainSession?.chips.map(\.label) == ["file task.py"] })
    }

    @Test func promotingAWindowForksTheMainSession() async throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, transport) = try store(fixture) { message in
            if message["type"]?.string == "session.open" {
                let id = message["fork"] == true ? "s-fork" : "s-main"
                return [ScriptedTransport.response(message, ["session": .string(id), "forked": message["fork"] ?? false])]
            }
            return ViewerStoreTests.sidecar(message)
        }
        let window = ViewerWindowModel(kind: .secondary)
        #expect(!window.isPanelPresented)
        store.ask(ChipFactory.file(ShellFixture.src + "task.py", commit: "c", shortener: store.shortener), from: window)
        #expect(store.mainSession?.chips.count == 1 && window.ownSession == nil)
        store.promote(window)
        let fork = try #require(window.ownSession)
        #expect(window.isPanelPresented && fork.forkOf === store.mainSession)
        fork.draft = "Fork question"
        await store.send(fork)
        let opens = transport.sent(type: "session.open")
        #expect(opens.count == 2 && opens[1]["resume"]?.string == "s-main" && opens[1]["fork"] == true)
        #expect(fork.sidecarID == "s-fork" && fork.stateLabel == "Claude Code session, forked")
    }

    @Test func appRequestsAnswerFromTheMainWindow() async throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, _) = try store(fixture)
        store.focus(step: 2)
        store.mainSession?.addChip(ChipFactory.step(try #require(store.pr?.step(2)), commit: "c"))
        let context = try await store.sidecarClient(store.sidecar, answer: SidecarAppRequest(id: "1", name: "selection_context", args: [:]))
        #expect(context["mode"]?.string == "by_step" && context["step"]?["id"]?.int == 2 && context["chips"]?.array?.count == 1)
        await #expect(throws: SidecarError.self) {
            _ = try await store.sidecarClient(store.sidecar, answer: SidecarAppRequest(id: "2", name: "find_symbol", args: ["name": "_pump"]))
        }
    }

    @Test func layoutsAreRequestedWithMeasuredSizes() async throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, transport) = try store(fixture)
        await store.layout(.pr)
        let request = try #require(transport.sent(type: "layout").last)
        #expect(request["diagram"]?["nodes"]?.array?.count == 3)
        #expect(request["sizes"]?["spec"]?["h"]?.int == 34 && request["sizes"]?["runtime"]?["h"]?.int == 26)
        // The fixture's one labelled edge, measured in the app's 8.5 pt font.
        let probes = try #require(request["edge_labels"]?["probes"])
        #expect(probes["h"]?.int == 14 && (probes["w"]?.double ?? 0) > 8)
        #expect(request["edge_labels"]?.object?.count == 1)
        // The scripted answer is not a layout, so the card shows the failure rather than nothing.
        if case .failed = store.layouts[.pr] {} else { Issue.record("expected a failed layout, got \(String(describing: store.layouts[.pr]))") }
    }
}
