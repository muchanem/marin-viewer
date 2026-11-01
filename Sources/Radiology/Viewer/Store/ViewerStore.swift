import AppKit
import Foundation
import Observation
import ViewerCore

/// A transient message at the bottom of the main window.
struct ViewerToast: Equatable, Identifiable, Sendable {
    let id = UUID()
    let text: String
}

/// State every window shares (DESIGN.md §5): the repository paths, the open PR decoded from the
/// wordbase, its review notes, the sessions and their memories, the sidecar, and the PR view's
/// mode, step, blame and reveal requests. Each window keeps its own `AppModel` reader and
/// `ViewerWindowModel`.
///
/// The PR view state lives here because exactly one window, the main one, shows the PR; the diff
/// reader reads and drives it through the seam below (see plans/shell.md).
@Observable @MainActor
final class ViewerStore {
    let paths: ViewerPaths
    private(set) var preparedPRs: [Int] = []
    private(set) var pr: ViewerPR?
    private(set) var loadingPR: Int?
    var loadError: String?
    private(set) var headWorktree: URL?
    private(set) var worktreeError: String?

    // MARK: Seam: the PR view state the diff reader observes

    /// By step or by file.
    var mode: ViewerMode = .byStep
    /// The step the main view shows in By step mode.
    private(set) var focusedStepID: Int?
    /// The latest request to scroll the main view to code.
    private(set) var revealRequest: RevealRequest?
    /// The blame gutter.
    var blame = false
    /// The Changes tab's "Hide tests"; on by default, as in the demo, and separate from
    /// Radiology's saved Hide Tests preference.
    var hidesTests = true
    /// The review note shown inline below its line and focused in the panel.
    private(set) var focusedNoteID: String?
    /// Files the reader should show whole, from "Show Whole File".
    private(set) var wholeFilePaths: Set<String> = []
    /// The code path's order, which a session's proposal can change.
    private(set) var stepOrder: [Int] = []
    /// Steps a session's applied proposal moved; they carry a "moved by session" tag.
    private(set) var movedSteps: Set<Int> = []

    // MARK: Notes, layouts, sessions

    private(set) var notes = ReviewNotes(notes: [])
    var notesError: String?
    private(set) var isPosting = false
    private(set) var layouts: [DiagramKey: DiagramLayoutPhase] = [:]
    /// The PR's session in the main window's panel.
    private(set) var mainSession: ViewerSession?
    private(set) var forks: [ViewerSession] = []
    private(set) var toast: ViewerToast?
    private(set) var sidecarError: String?

    let sidecar: SidecarClient
    let mainWindow: ViewerWindowModel
    /// Set by the main window: SwiftUI's `openWindow` for secondary code windows.
    @ObservationIgnored var openCodeWindow: ((CodeWindowRequest) -> Void)?
    @ObservationIgnored weak var mainReader: AppModel? {
        didSet { mainWindow.reader = mainReader }
    }
    @ObservationIgnored private let writeNotes: @Sendable (URL, String) throws -> Void
    @ObservationIgnored private let makeLoader: @Sendable (ViewerPaths) throws -> ViewerPRLoader
    @ObservationIgnored private var loader: ViewerPRLoader?
    @ObservationIgnored private var worktreeTask: Task<URL?, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var revealRevision = 0
    @ObservationIgnored private let resolver = ViewerLocationResolver()
    @ObservationIgnored private var forkOwners: [UUID: WeakWindow] = [:]

    private struct WeakWindow { weak var window: ViewerWindowModel? }

    init(paths: ViewerPaths = ViewerPaths(), sidecar: SidecarClient? = nil,
         writeNotes: (@Sendable (URL, String) throws -> Void)? = nil,
         makeLoader: (@Sendable (ViewerPaths) throws -> ViewerPRLoader)? = nil) {
        self.paths = paths
        self.sidecar = sidecar ?? SidecarClient(makeTransport: { try ViewerStore.processTransport(paths: paths) })
        self.writeNotes = writeNotes ?? { url, text in try Data(text.utf8).write(to: url, options: .atomic) }
        self.makeLoader = makeLoader ?? { try ViewerPRLoader(paths: $0) }
        mainWindow = ViewerWindowModel(kind: .main)
        self.sidecar.delegate = self
        refreshPreparedPRs()
    }

    static func processTransport(paths: ViewerPaths) throws -> any SidecarTransport {
        guard FileManager.default.fileExists(atPath: paths.sidecarScript.path) else {
            throw SidecarError.unavailable("The sidecar is not built. Run `npm ci && npm run build` in \(paths.sidecar.path).")
        }
        guard let node = paths.resolveNode() else {
            throw SidecarError.unavailable("Node.js was not found; the sidecar needs node 22 or later.")
        }
        return ProcessSidecarTransport(node: node, script: paths.sidecarScript,
                                       environment: SidecarEnvironment.child(paths: paths, node: node))
    }

    func refreshPreparedPRs() { preparedPRs = paths.preparedPRs() }

    var isReviewing: Bool { pr != nil }
    var shortener: PathShortener { PathShortener(system: pr?.system) }
    var orderedSteps: [PRStep] { stepOrder.compactMap { pr?.step($0) } }
    var focusedStep: PRStep? { focusedStepID.flatMap { pr?.step($0) } }
    var focusedNote: ReviewNote? { focusedNoteID.flatMap { notes[$0] } }
    var draftNotePaths: Set<String> { Set(notes.notes.filter { $0.status == .draft }.map(\.path)) }

    // MARK: - Opening a PR

    /// Opens prepared PR `number` from the wordbase. The main reader moves to the Marin clone
    /// when it shows another repository, and its sidebar starts on Code path.
    func openPR(_ number: Int) async {
        loadingPR = number
        loadError = nil
        do {
            let loader = try loader ?? makeLoader(paths)
            self.loader = loader
            let loaded = try await loader.load(number)
            guard loadingPR == number else { return }
            install(loaded)
            startWorktree(loader: loader, head: loaded.head)
            requestLayouts(for: loaded)
        } catch {
            if loadingPR == number { loadError = error.localizedDescription }
        }
        if loadingPR == number { loadingPR = nil }
    }

    /// Makes `loaded` the open PR. Public for tests and snapshots, which load without git.
    func install(_ loaded: ViewerPR) {
        if let session = mainSession, session.phase == .memories {
            keepInBackground(session, reason: "another PR opened")
        }
        pr = loaded
        notes = loaded.wordbase.notes
        stepOrder = loaded.wordbase.codePath.map(\.id)
        movedSteps = []
        focusedStepID = stepOrder.first
        focusedNoteID = nil
        revealRequest = nil
        wholeFilePaths = []
        mode = .byStep
        blame = false
        layouts = [:]
        headWorktree = nil
        worktreeError = nil
        mainSession = ViewerSession(pr: loaded.number)
        forks = []
        mainWindow.zoomedStep = nil
        mainWindow.descriptionLevel = 1
        mainWindow.isPanelPresented = true
        mainWindow.panelTab = .session
        if let reader = mainReader {
            if reader.attachedRoot?.standardizedFileURL.resolvingSymlinksInPath() != paths.marin.standardizedFileURL.resolvingSymlinksInPath() {
                reader.openRepository(paths.marin)
            }
            reader.mode = .steps
        }
    }

    func closePR() {
        if let session = mainSession, session.phase == .memories {
            keepInBackground(session, reason: "the PR closed")
        }
        pr = nil
        mainSession = nil
        layouts = [:]
        if let reader = mainReader, reader.mode == .steps { reader.mode = .files }
    }

    private func startWorktree(loader: ViewerPRLoader, head: String) {
        worktreeTask?.cancel()
        worktreeTask = Task { [weak self] in
            do {
                let url = try await loader.worktree(head: head)
                guard let self, self.pr?.head == head else { return nil }
                self.headWorktree = url
                return url
            } catch {
                self?.worktreeError = error.localizedDescription
                return nil
            }
        }
    }

    /// The session's cwd and secondary windows' root: the head worktree, else the Marin clone.
    func readyRoot() async -> URL {
        if let headWorktree { return headWorktree }
        if let task = worktreeTask, let url = await task.value { return url }
        return paths.marin
    }

    // MARK: - Diagrams

    func diagram(_ key: DiagramKey) -> Diagram? {
        switch key {
        case .system: pr?.system?.diagram
        case .pr: pr?.wordbase.diagrams.pr
        case .step(let id): pr?.wordbase.diagrams.diagram(forStep: id)
        }
    }

    func hasStepDiagram(_ step: Int?) -> Bool { step.map { pr?.wordbase.diagrams.diagram(forStep: $0) != nil } ?? false }

    private func requestLayouts(for pr: ViewerPR) {
        var keys: [DiagramKey] = [.system, .pr]
        keys += pr.wordbase.diagrams.steps.keys.compactMap(Int.init).sorted().map(DiagramKey.step)
        for key in keys where diagram(key) != nil {
            Task { await layout(key) }
        }
    }

    /// Asks the sidecar to lay `key` out with box sizes measured in the app's font.
    func layout(_ key: DiagramKey) async {
        guard let diagram = diagram(key), let number = pr?.number else { return }
        layouts[key] = .loading
        do {
            let result = try await sidecar.request([
                "type": "layout",
                "diagram": try JSONValue.encoding(diagram),
                "sizes": DiagramMetrics.sizes(for: diagram, key: key),
            ])
            guard pr?.number == number else { return }
            layouts[key] = .ready(try result.decode(DiagramLayoutResult.self))
        } catch {
            guard pr?.number == number else { return }
            layouts[key] = .failed(error.localizedDescription)
        }
    }

    /// Installs a layout directly (tests and snapshots).
    func setLayout(_ result: DiagramLayoutResult, for key: DiagramKey) { layouts[key] = .ready(result) }

    // MARK: - Seam: actions the reader and the shell call

    /// Shows step `id` By step and drops any reveal into the previous step.
    func focus(step id: Int) {
        guard pr?.step(id) != nil else { return }
        focusedStepID = id
        mode = .byStep
        revealRequest = nil
    }

    /// The step after `id` in the current order, for the main view's "Next" link.
    func step(after id: Int) -> PRStep? {
        guard let index = stepOrder.firstIndex(of: id), index + 1 < stepOrder.count else { return nil }
        return pr?.step(stepOrder[index + 1])
    }

    /// Scrolls the main view to code. By step, a location inside the current step's excerpts
    /// stays in the step; anything else switches to By file. A `function` without a line is
    /// resolved against the head checkout, then against the code path's fallback lines.
    func reveal(path: String, line: Int? = nil, function: String? = nil) {
        let inStep = mode == .byStep && (focusedStep?.covers(path: path, line: line, function: function) ?? false)
        if !inStep { mode = .byFile }
        revealRevision += 1
        let revision = revealRevision
        revealRequest = RevealRequest(path: path, line: line ?? fallbackLine(path: path, function: function),
                                      function: function, inStep: inStep, revision: revision)
        guard line == nil, let function else { return }
        Task {
            let root = headWorktree ?? paths.marin
            guard let resolved = await resolver.line(of: function, path: path, root: root),
                  revealRequest?.revision == revision else { return }
            revealRequest = RevealRequest(path: path, line: resolved, function: function, inStep: inStep, revision: revision)
        }
    }

    /// Opens a file By file, as a Changes row, a search hit or a note's location link does.
    func open(path: String, line: Int? = nil) {
        mode = .byFile
        revealRevision += 1
        revealRequest = RevealRequest(path: path, line: line, function: nil, inStep: false, revision: revealRevision)
    }

    func toggleWholeFile(_ path: String) {
        if wholeFilePaths.contains(path) { wholeFilePaths.remove(path) } else { wholeFilePaths.insert(path) }
    }

    func showWholeFile(_ path: String) { wholeFilePaths.insert(path) }

    /// Shows a note inline and focuses its card in the panel; nil clears the focus.
    func focus(note id: String?) {
        focusedNoteID = focusedNoteID == id ? nil : id
        guard id != nil else { return }
        mainWindow.isPanelPresented = true
        mainWindow.panelTab = .notes
    }

    /// The note card's location link: focus the note and open its line By file.
    func revealNote(_ id: String) {
        guard let note = notes[id] else { return }
        focusedNoteID = id
        open(path: note.path, line: note.line)
    }

    /// Adds `chip` to the session `window` asks into: its own when promoted, else the PR's main
    /// session. Pending memories are kept first, since a new question starts a new session.
    func ask(_ chip: Chip, from window: ViewerWindowModel? = nil) {
        let asking = window?.ownSession != nil ? window! : mainWindow
        var session = asking.ownSession ?? mainSession
        if let pending = session, pending.phase == .memories {
            keepInBackground(pending, reason: "a new question started")
            session = asking.ownSession ?? mainSession
        }
        guard let session else {
            showToast("Open a prepared PR to ask its session.")
            return
        }
        session.addChip(chip)
        asking.isPanelPresented = true
        asking.panelTab = .session
    }

    private func fallbackLine(path: String, function: String?) -> Int? {
        guard let function, let pr else { return nil }
        for step in orderedSteps { if let line = step.fallbackLine(path: path, function: function) { return line } }
        return pr.wordbase.codePath.lazy.compactMap { $0.fallbackLine(path: path, function: function) }.first
    }

    // MARK: - Secondary windows

    func openInNewWindow(path: String, line: Int? = nil) {
        let root = (headWorktree ?? paths.marin).path
        openCodeWindow?(CodeWindowRequest(path: path, line: line, root: root))
    }

    /// "Promote to Session": forks the main session for `window` and gives it its own panel.
    func promote(_ window: ViewerWindowModel) {
        guard window.ownSession == nil, let pr, let main = mainSession else { return }
        let fork = ViewerSession(pr: pr.number, forkOf: main)
        forks.append(fork)
        forkOwners[fork.id] = WeakWindow(window: window)
        window.ownSession = fork
        window.isPanelPresented = true
        window.panelTab = .session
    }

    // MARK: - Review notes

    func apply(_ action: ReviewAction, to id: String) {
        do {
            var updated = notes
            try updated.apply(action, to: id)
            notes = updated
            saveNotes()
        } catch {
            notesError = "\(error)"
        }
    }

    /// Adds a draft from a session's `draft_review_note`.
    func addDraftNote(path: String, line: Int, side: ReviewNote.Side, severity: ReviewNote.Severity,
                      l1: String, l2: String?, commit: String?) {
        guard let pr else { return }
        let now = Date.now.formatted(.iso8601)
        let note = ReviewNote(id: "s-\(UUID().uuidString.prefix(8).lowercased())", path: path, line: line, side: side,
                              commit: commit ?? pr.head, severity: severity, who: "review session", l1: l1,
                              l2: l2 ?? "", created: now, updated: now)
        notes = ReviewNotes(notes: notes.notes + [note])
        saveNotes()
    }

    private func saveNotes() {
        guard let pr else { return }
        do {
            try writeNotes(pr.directory.appending(path: "notes.jsonl"), try notes.jsonl())
            notesError = nil
        } catch {
            notesError = "Could not save notes.jsonl: \(error.localizedDescription)"
        }
    }

    /// Posts the approved notes as one pending review through the sidecar, after the confirm
    /// sheet showed `notes.postConfirmationText`. This is the only path that posts to GitHub.
    func postApprovedNotes() async {
        guard let pr, !isPosting else { return }
        let approved = notes.approved
        guard !approved.isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            let payload: [JSONValue] = try approved.map { note in
                guard case .object(var object) = try JSONValue.encoding(note) else { return .null }
                object["body"] = .string(note.l2.isEmpty ? note.l1 : "\(note.l1)\n\n\(note.l2)")
                return .object(object)
            }
            let result = try await sidecar.request([
                "type": "review.post", "pr": .number(Double(pr.number)), "notes": .array(payload),
                "repo": .string(pr.header.repo ?? "marin-community/marin"),
            ])
            var ids: [String: Int] = [:]
            for comment in result["comments"]?.array ?? [] {
                if let note = comment["note_id"]?.string, let id = comment["github_comment_id"]?.int { ids[note] = id }
            }
            var updated = notes
            try updated.markPosted(ids)
            notes = updated
            saveNotes()
            showToast("Posted \(ids.count) review note\(ids.count == 1 ? "" : "s") to #\(pr.number).")
        } catch {
            notesError = "Posting failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sessions

    func session(sidecarID: String) -> ViewerSession? {
        ([mainSession].compactMap { $0 } + forks).first { $0.sidecarID == sidecarID }
    }

    /// Opens the sidecar session on first use: the PR scope in the head worktree, resuming the
    /// preparation session when the wordbase names one, or forking the main session.
    func openIfNeeded(_ session: ViewerSession) async throws {
        guard session.sidecarID == nil, let pr else { return }
        session.phase = .opening
        var message: [String: JSONValue] = [
            "type": "session.open",
            "scope": ["pr": .number(Double(pr.number))],
            "cwd": .string(await readyRoot().path),
        ]
        if let parent = session.forkOf {
            try await openIfNeeded(parent)
            if let parentID = parent.sidecarID {
                message["resume"] = .string(parentID)
                message["fork"] = true
            }
        } else if UUID(uuidString: pr.header.sessionID) != nil {
            message["resume"] = .string(pr.header.sessionID)
        }
        do {
            let result = try await sidecar.request(message)
            session.sidecarID = result["session"]?.string
            session.resumedID = result["resumed"]?.string
            session.phase = .ready
            sidecarError = nil
        } catch {
            session.phase = .notStarted
            sidecarError = error.localizedDescription
            throw error
        }
    }

    /// Sends the draft and chips. Enter in the input calls this.
    func send(_ session: ViewerSession) async {
        let text = session.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let chips = session.chips
        guard !text.isEmpty || !chips.isEmpty, !session.isBusy, session.phase != .closing else { return }
        session.draft = ""
        session.chips = []
        session.entries.append(SessionEntry(kind: .user(text: text, chips: chips)))
        session.isBusy = true
        do {
            try await openIfNeeded(session)
            guard let id = session.sidecarID else { throw SidecarError.failed("The sidecar opened no session.") }
            _ = try await sidecar.request([
                "type": "session.send", "session": .string(id), "text": .string(text),
                "chips": try JSONValue.encoding(chips),
            ])
        } catch {
            session.isBusy = false
            session.entries.append(SessionEntry(kind: .failure(error.localizedDescription)))
        }
    }

    func interrupt(_ session: ViewerSession) {
        guard let id = session.sidecarID else { return }
        try? sidecar.post(["type": "session.interrupt", "session": .string(id)])
    }

    /// The panel's ×: runs the closing turn, which proposes memories, then shows them.
    func closeSession(_ session: ViewerSession) async {
        guard session.phase != .closing, session.phase != .memories else { return }
        guard let id = session.sidecarID else {
            session.memories = []
            session.phase = .memories
            return
        }
        session.phase = .closing
        do {
            _ = try await sidecar.request(["type": "session.close", "session": .string(id), "propose_notes": true])
        } catch {
            session.lastError = error.localizedDescription
        }
        session.isBusy = false
        session.phase = .memories
    }

    func dropMemory(_ memory: ProposedMemory, from session: ViewerSession) {
        session.memories.removeAll { $0.id == memory.id }
    }

    /// Keeps the memories still listed (Done, a new session, a window close or quitting) and
    /// replaces a closed main session with a fresh one that resumes the PR's scope.
    func keepMemories(_ session: ViewerSession, reason: String) async {
        guard let kept = retireMemories(session) else { return }
        await sendKeep(kept, of: session, reason: reason)
    }

    /// Keeps memories without waiting: the session is retired at once, so whatever comes next
    /// (a chip, another PR) lands in the fresh session, and `notes.keep` follows.
    private func keepInBackground(_ session: ViewerSession, reason: String) {
        guard let kept = retireMemories(session) else { return }
        Task { await sendKeep(kept, of: session, reason: reason) }
    }

    /// Closes a session waiting on its memories and puts a fresh one in its place.
    private func retireMemories(_ session: ViewerSession) -> [ProposedMemory]? {
        guard session.phase == .memories else { return nil }
        session.phase = .closed
        if session === mainSession, let pr { mainSession = ViewerSession(pr: pr.number) }
        if let owner = forkOwners.removeValue(forKey: session.id)?.window, owner.ownSession === session { owner.ownSession = nil }
        return session.memories
    }

    private func sendKeep(_ kept: [ProposedMemory], of session: ViewerSession, reason: String) async {
        guard !kept.isEmpty, let id = session.sidecarID else {
            showToast("No notes kept.")
            return
        }
        do {
            _ = try await sidecar.request(["type": "notes.keep", "session": .string(id), "notes": try JSONValue.encoding(kept)])
            showToast("\(kept.count) note\(kept.count == 1 ? "" : "s") kept: \(reason).")
        } catch {
            showToast("Could not keep the notes: \(error.localizedDescription)")
        }
    }

    /// Every session waiting on its memories, for window close and quit.
    var sessionsWithPendingMemories: [ViewerSession] {
        ([mainSession].compactMap { $0 } + forks).filter { $0.phase == .memories }
    }

    func keepAllPendingMemories(reason: String) async {
        for session in sessionsWithPendingMemories { await keepMemories(session, reason: reason) }
    }

    // MARK: - View changes from the session

    func applyViewChange(_ id: UUID, in session: ViewerSession) {
        guard let index = session.viewChanges.firstIndex(where: { $0.id == id }), let pr else { return }
        var change = session.viewChanges[index]
        if change.isApplied {
            if let previous = change.previousOrder { stepOrder = previous }
            movedSteps = change.previousMoved
            change.isApplied = false
        } else {
            change.previousOrder = stepOrder
            change.previousMoved = movedSteps
            if let order = change.order {
                let original = pr.wordbase.codePath.map(\.id)
                stepOrder = StepOrdering.normalized(order, steps: original)
                movedSteps = StepOrdering.moved(original: original, reordered: stepOrder)
            }
            if let step = change.step ?? movedSteps.sorted().first.flatMap({ moved in stepOrder.first { $0 == moved } }) {
                focus(step: step)
            }
            change.isApplied = true
        }
        session.viewChanges[index] = change
    }

    // MARK: - Toasts

    func showToast(_ text: String) {
        let toast = ViewerToast(text: text)
        self.toast = toast
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.2))
            guard !Task.isCancelled, self?.toast?.id == toast.id else { return }
            self?.toast = nil
        }
    }

    /// Quit: keep pending memories, then stop the sidecar.
    func prepareForTermination() async {
        await keepAllPendingMemories(reason: "the app quit")
        sidecar.stop()
    }
}

// MARK: - Sidecar events and requests

extension ViewerStore: SidecarClientDelegate {
    func sidecarClient(_ client: SidecarClient, received event: SidecarEvent) {
        switch event {
        case .delta(let id, let text):
            guard let session = session(sidecarID: id), session.phase != .closing else { return }
            session.appendDelta(text)
        case .turnResult(let id, let cost, let isError, let text):
            guard let session = session(sidecarID: id) else { return }
            session.costUSD += cost
            if session.phase != .closing { session.isBusy = false }
            if isError { session.entries.append(SessionEntry(kind: .failure(text ?? "The turn ended with an error."))) }
        case .uiCommand(let id, let name, let args):
            handleUICommand(name, args: args, session: session(sidecarID: id) ?? mainSession)
        case .notesProposed(let id, let notes):
            session(sidecarID: id)?.memories = notes
        case .error(let id, let message):
            if let id, let session = session(sidecarID: id) {
                session.entries.append(SessionEntry(kind: .failure(message)))
                session.isBusy = false
            } else {
                sidecarError = message
            }
        case .exited(let reason):
            sidecarError = reason
            for session in [mainSession].compactMap({ $0 }) + forks where session.sidecarID != nil {
                session.sidecarID = nil
                session.isBusy = false
                if session.phase == .ready { session.phase = .notStarted }
            }
        }
    }

    func handleUICommand(_ name: String, args: [String: JSONValue], session: ViewerSession?) {
        switch name {
        case "focus_code_path":
            let change = ViewChange(reason: args["reason"]?.string ?? "The session proposes a change to the code path.",
                                    order: args["order"]?.array?.compactMap(\.int), step: args["step"]?.int)
            guard let session else { return }
            session.viewChanges.append(change)
            session.entries.append(SessionEntry(kind: .viewChange(change.id)))
        case "open_location":
            guard let path = args["path"]?.string else { return }
            reveal(path: path, line: args["line"]?.int, function: args["function"]?.string)
        case "draft_review_note":
            guard let path = args["path"]?.string, let line = args["line"]?.int, let l1 = args["l1"]?.string else { return }
            addDraftNote(path: path, line: line, side: ReviewNote.Side(rawValue: args["side"]?.string ?? "head") ?? .head,
                         severity: ReviewNote.Severity(rawValue: args["severity"]?.string ?? "medium") ?? .medium,
                         l1: l1, l2: args["l2"]?.string, commit: args["commit"]?.string)
            session?.entries.append(SessionEntry(kind: .notice("Drafted a review note at \(shortener.short(path)):\(line).")))
        default:
            break
        }
    }

    func sidecarClient(_ client: SidecarClient, answer request: SidecarAppRequest) async throws -> JSONValue {
        switch request.name {
        case "find_symbol":
            guard let name = request.args["name"]?.string else { throw SidecarError.failed("find_symbol needs a name") }
            return try findSymbol(name)
        case "selection_context":
            return selectionContext()
        default:
            throw SidecarError.failed("The viewer does not answer \(request.name).")
        }
    }

    /// Definitions of `name` in the main reader's SCIP index (the checkout it has open).
    func findSymbol(_ name: String) throws -> JSONValue {
        guard let reader = mainReader, !reader.semantics.index.searchEntries.isEmpty else {
            throw SidecarError.failed("The viewer has no semantic index for this checkout yet.")
        }
        let last = name.split(whereSeparator: { $0 == "." || $0 == ":" }).last.map(String.init) ?? name
        let matches = reader.semantics.index.searchEntries.filter { $0.name == name || $0.name == last }.prefix(20)
        return .object([
            "root": .string(reader.repository?.root.path ?? ""),
            "definitions": .array(matches.map { entry in
                .object(["name": .string(entry.name), "path": .string(entry.position.path),
                         "line": .number(Double(entry.position.range.startLine + 1)),
                         "definitions": .number(Double(entry.definitionCount))])
            }),
        ])
    }

    /// What the main window shows: mode, step, chips and focused note.
    func selectionContext() -> JSONValue {
        var context: [String: JSONValue] = ["mode": .string(mode == .byStep ? "by_step" : "by_file")]
        if let pr { context["pr"] = .number(Double(pr.number)); context["head"] = .string(pr.head) }
        if let step = focusedStep { context["step"] = .object(["id": .number(Double(step.id)), "title": .string(step.title)]) }
        if let note = focusedNote { context["note"] = .object(["id": .string(note.id), "path": .string(note.path), "line": .number(Double(note.line))]) }
        if let reveal = revealRequest {
            context["location"] = .object(["path": .string(reveal.path), "line": reveal.line.map { .number(Double($0)) } ?? .null])
        }
        context["chips"] = (try? JSONValue.encoding(mainSession?.chips ?? [])) ?? .array([])
        return .object(context)
    }
}
