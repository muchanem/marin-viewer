import Foundation
import Testing
import ViewerCore
@testable import Radiology

/// The shell driving the diff reader through the store's seam, on the fixture's synthetic
/// review document (no git).
@Suite(.serialized) @MainActor
struct ViewerReaderWiringTests {
    private func store(_ fixture: ShellFixture) throws -> (ViewerStore, DiffReaderModel) {
        let transport = ScriptedTransport(script: ViewerStoreTests.sidecar)
        let store = ViewerStore(paths: fixture.paths, sidecar: SidecarClient(makeTransport: { transport }), writeNotes: { _, _ in })
        let pr = try fixture.loadPR()
        store.install(pr)
        store.install(document: ShellFixture.document(for: pr))
        return (store, try #require(store.diffReader))
    }

    private static let machine = ShellFixture.src + "backends/local/machine.py"
    private static let task = ShellFixture.src + "task.py"

    @Test func theReaderStartsWhereTheShellWasAndTheShellReadsItsState() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let transport = ScriptedTransport(script: ViewerStoreTests.sidecar)
        let store = ViewerStore(paths: fixture.paths, sidecar: SidecarClient(makeTransport: { transport }), writeNotes: { _, _ in })
        let pr = try fixture.loadPR()
        store.install(pr)
        // Clicked while the document loads.
        store.focus(step: 3)
        store.blame = true
        store.install(document: ShellFixture.document(for: pr))
        let reader = try #require(store.diffReader)
        #expect(reader.stepID == 3 && reader.mode == .byStep && reader.showBlame)
        #expect(reader.notes.notes.count == 3)

        store.mode = .byFile
        #expect(reader.mode == .byFile)
        reader.focus(step: 2)
        #expect(store.focusedStepID == 2 && store.mode == .byStep)
        reader.showBlame = false
        #expect(!store.blame)
        store.toggleWholeFile(Self.task)
        #expect(reader.wholeFile == [Self.task] && store.wholeFilePaths == [Self.task])
    }

    @Test func aReorderedCodePathIsTheReadersStepOrder() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, reader) = try store(fixture)
        let session = try #require(store.mainSession)
        session.sidecarID = "s-1"
        store.sidecarClient(store.sidecar, received: .uiCommand(session: "s-1", name: "focus_code_path",
                                                               args: ["order": [3, 1, 2], "reason": "Readiness first."]))
        store.applyViewChange(try #require(session.viewChanges.first).id, in: session)
        #expect(reader.orderedSteps.map(\.id) == [3, 1, 2])
        #expect(reader.stepID == 3 && reader.stepPosition?.index == 1 && reader.nextStep?.id == 1)

        reader.setStepOrder([2, 2, 99])
        #expect(reader.orderedSteps.map(\.id) == [2, 1, 3])
    }

    @Test func aStepDiagramBoxScrollsTheReaderToItsCode() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, reader) = try store(fixture)
        let at = try ShellFixture.location(Self.machine, function: "LocalMachineFactory.create_task")
        store.openStepDiagram(2, in: store.mainWindow)
        store.openCode(of: .init(id: "ct", label: "create_task", at: at, x: 0, y: 0, w: 90, h: 34))
        // Step 2's excerpt holds the declaration, so the reader stays on the step and flashes it.
        #expect(reader.mode == .byStep && reader.stepID == 2)
        #expect(reader.scrollTarget?.cardID == "s2:0" && reader.scrollTarget?.flash == true)
        #expect(store.revealRequest?.line == 1029)

        store.focus(step: 1)
        store.openCode(of: .init(id: "ct", label: "create_task", at: at, x: 0, y: 0, w: 90, h: 34))
        #expect(reader.mode == .byFile && reader.scrollTarget?.cardID == "f:\(Self.machine)")
    }

    @Test func codeOutsideThePRsFilesOpensACodeWindow() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, reader) = try store(fixture)
        var opened: [CodeWindowRequest] = []
        store.openCodeWindow = { opened.append($0) }
        store.reveal(path: ShellFixture.src + "machine.py", line: 12)
        store.open(path: "lib/shellbox/tests/conftest.py")
        #expect(opened.map(\.path) == [ShellFixture.src + "machine.py", "lib/shellbox/tests/conftest.py"])
        #expect(opened.first?.line == 12 && reader.mode == .byStep)

        reader.openInNewWindow(DiffCodeTarget(path: Self.task, line: 50))
        #expect(opened.last == CodeWindowRequest(path: Self.task, line: 50, root: fixture.paths.marin.path))
    }

    @Test func goToDefinitionScrollsInsideThePROpensAWindowOutsideAndSaysWhenNothingIsFound() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, reader) = try store(fixture)
        var opened: [CodeWindowRequest] = []
        store.openCodeWindow = { opened.append($0) }
        let origin = DiffCodeTarget(path: Self.task, line: 60)

        reader.goToDefinition(DiffDefinitionRequest(symbol: "LocalMachineFactory.create_task", origin: origin, destination: nil))
        #expect(reader.mode == .byFile && reader.scrollTarget?.cardID == "f:\(Self.machine)" && opened.isEmpty)

        reader.goToDefinition(DiffDefinitionRequest(symbol: "Machine", origin: origin,
                                                    destination: DiffCodeTarget(path: ShellFixture.src + "machine.py", line: 20)))
        #expect(opened.map(\.path) == [ShellFixture.src + "machine.py"] && opened.first?.line == 20)

        reader.goToDefinition(DiffDefinitionRequest(symbol: "nowhere", origin: origin, destination: nil))
        #expect(store.toast?.text == "No definition of nowhere in this PR's files or the checkout's index.")
    }

    @Test func notesOpenInTheReaderAndFocusTheirCardInThePanel() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, reader) = try store(fixture)
        store.mainWindow.isPanelPresented = false
        store.focus(note: "f2")
        #expect(reader.expandedNoteID == "f2" && store.focusedNoteID == "f2")
        #expect(store.mainWindow.isPanelPresented && store.mainWindow.panelTab == .notes)
        store.focus(note: "f2")
        #expect(reader.expandedNoteID == nil && store.focusedNoteID == nil)

        // A gutter dot in the reader.
        store.mainWindow.panelTab = .session
        reader.toggleNote("f1")
        #expect(store.focusedNoteID == "f1" && store.mainWindow.panelTab == .notes)

        store.revealNote("f2")
        #expect(reader.expandedNoteID == "f2" && reader.mode == .byFile && reader.scrollTarget?.cardID == "f:\(Self.task)")
    }

    @Test func askingFromTheReaderAddsAChipAndTheSelectionAnswersCommandGreaterThan() async throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, reader) = try store(fixture)
        let session = try #require(store.mainSession)
        store.mainWindow.panelTab = .notes
        reader.ask(reader.fileChip(path: Self.task))
        #expect(session.chips.map(\.label) == ["file \(Self.task)"] && store.mainWindow.panelTab == .session)

        // A click on a box, then a newer code selection: the selection wins.
        store.mainWindow.lastAskTarget = Chip(kind: .box, commit: "c", label: "component Task")
        reader.selectionChanged(.init(cardID: "s1:0", path: Self.task, lines: 50...52, text: "x = 1"), in: "s1:0")
        #expect(store.mainWindow.lastAskTarget == nil)
        let chip = try #require(ViewerAsk.chip(store: store, window: store.mainWindow))
        #expect(chip.kind == .selection && chip.lines == 50...52 && chip.symbol == "TaskSpec")

        let context = try await store.sidecarClient(store.sidecar, answer: SidecarAppRequest(id: "1", name: "selection_context", args: [:]))
        #expect(context["selection"]?["path"]?.string == Self.task && context["selection"]?["text"]?.string == "x = 1")
        #expect(context["selection"]?["lines"]?.array?.compactMap(\.int) == [50, 52])

        // Collapsing that card's selection clears it; another card's empty selection does not.
        reader.selectionChanged(nil, in: "s1:1")
        #expect(reader.selection != nil)
        reader.selectionChanged(nil, in: "s1:0")
        #expect(reader.selection == nil)
    }

    @Test func closingOrReopeningAPRDropsItsReader() throws {
        let fixture = try ShellFixture.make()
        defer { fixture.remove() }
        let (store, _) = try store(fixture)
        store.install(try fixture.loadPR())
        #expect(store.diffReader == nil && store.document == nil && store.focusedStepID == 1)
        store.install(document: ShellFixture.document(for: try fixture.loadPR()))
        store.closePR()
        #expect(store.diffReader == nil && store.document == nil)
    }
}
