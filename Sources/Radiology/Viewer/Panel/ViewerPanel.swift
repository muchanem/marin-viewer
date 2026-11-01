import SwiftUI
import ViewerCore

/// The right panel of a PR window (DESIGN.md §2): Session, Review notes and Context tabs under
/// the session's header. Its × closes the session, which asks for memories first; ⌥⌘I only
/// hides the panel.
struct ViewerPanel: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        @Bindable var window = window
        VStack(spacing: 0) {
            if let session = window.ownSession ?? store.mainSession {
                PanelHeader(session: session)
                Picker("Panel", selection: $window.panelTab) {
                    Text("Session").tag(ViewerWindowModel.PanelTab.session)
                    Text("Review notes (\(store.notes.notes.count))").tag(ViewerWindowModel.PanelTab.notes)
                    Text("Context").tag(ViewerWindowModel.PanelTab.context)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, Theme.inset)
                .padding(.bottom, Theme.spacing)
                Divider()
                if session.phase == .memories || session.phase == .closing {
                    MemoriesView(session: session)
                } else {
                    switch window.panelTab {
                    case .session:
                        SessionTranscript(session: session)
                        Divider()
                        SessionComposer(session: session)
                    case .notes:
                        ReviewNotesTab()
                    case .context:
                        ContextInspectorView()
                    }
                }
            } else {
                ContentUnavailableView("No Session", systemImage: "bubble.left.and.text.bubble.right",
                                       description: Text("Open a prepared PR with File > Open PR."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.background)
        .inspectorColumnWidth(min: 320, ideal: 390, max: 560)
    }
}

/// "PR #10640 session", the session's state and cwd, and × to close it.
struct PanelHeader: View {
    @Environment(ViewerStore.self) private var store
    let session: ViewerSession

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title).font(.headline)
                Text("\(session.stateLabel) · cwd \(store.pr?.repoName ?? "marin") @ \(store.pr?.head.prefix(7) ?? "")")
                    .font(ViewerFonts.meta).foregroundStyle(.secondary).lineLimit(2)
                    .help(store.headWorktree?.path ?? store.paths.marin.path)
            }
            Spacer(minLength: 0)
            Button("Close Session and Save Notes", systemImage: "xmark") {
                Task { await store.closeSession(session) }
            }
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            .disabled(session.phase == .closing || session.phase == .memories)
            .help("Close this session. It proposes notes for the wordbase first.")
        }
        .padding(Theme.inset)
    }
}

/// The preparation record, then the conversation, with proposed view changes inline.
struct SessionTranscript: View {
    @Environment(ViewerStore.self) private var store
    let session: ViewerSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if session.forkOf == nil { PreparationRecord() }
                    ForEach(session.entries) { entry in
                        entryView(entry).id(entry.id)
                    }
                    if session.isBusy {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Working…").font(ViewerFonts.meta).foregroundStyle(.secondary)
                            Spacer()
                            Button("Stop") { store.interrupt(session) }.buttonStyle(.link).font(ViewerFonts.meta)
                        }
                        .id("busy")
                    }
                    if let error = store.sidecarError, session.entries.isEmpty {
                        Text(error).font(ViewerFonts.meta).foregroundStyle(Color.viewerBad)
                    }
                }
                .padding(Theme.inset)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.entries.last?.kind) {
                if let last = session.entries.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private func entryView(_ entry: SessionEntry) -> some View {
        switch entry.kind {
        case .user(let text, let chips):
            VStack(alignment: .leading, spacing: 4) {
                if !chips.isEmpty { ChipFlow(chips: chips) }
                if !text.isEmpty { Text(text).font(ViewerFonts.body) }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.viewerSoft, in: .rect(cornerRadius: 8))
        case .agent(let text):
            Text(viewerMarkdown(text)).font(ViewerFonts.body).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .viewChange(let id):
            if let change = session.viewChange(id) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(change.reason).font(ViewerFonts.summary)
                    Spacer(minLength: 4)
                    Button(change.isApplied ? "Undo" : "Apply") { store.applyViewChange(id, in: session) }
                        .controlSize(.small)
                }
                .padding(8)
                .background(Color.viewerAccentSoft, in: .rect(cornerRadius: 6))
            }
        case .notice(let text):
            Text(text).font(ViewerFonts.meta).foregroundStyle(.secondary)
        case .failure(let text):
            Text(text).font(ViewerFonts.meta).foregroundStyle(Color.viewerBad)
        }
    }
}

/// Markdown for agent replies: inline styles, with paragraphs kept.
func viewerMarkdown(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}

/// "Preparation turn, 2026-10-30 · wrote description, 8 steps, 4 diagrams, 2 draft notes".
struct PreparationRecord: View {
    @Environment(ViewerStore.self) private var store
    @State private var isExpanded = false

    var body: some View {
        if let pr = store.pr {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Self.lines(pr), id: \.self) { line in
                        Text("• " + line).font(ViewerFonts.meta).foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(Self.summary(pr, drafts: store.notes.draftCount)).font(ViewerFonts.meta).foregroundStyle(.secondary)
            }
        }
    }

    static func summary(_ pr: ViewerPR, drafts: Int) -> String {
        let steps = pr.wordbase.codePath.count
        let diagrams = pr.stepDiagramCount
        return "Preparation turn, \(PRDescriptionCard.day(pr.header.preparedAt)) · wrote description, \(steps) \(steps == 1 ? "step" : "steps"), "
            + "\(diagrams) \(diagrams == 1 ? "diagram" : "diagrams"), \(drafts) draft \(drafts == 1 ? "note" : "notes")"
    }

    static func lines(_ pr: ViewerPR) -> [String] {
        var lines = ["Read the diff at \(pr.head.prefix(7)) and its merge base \(pr.base.prefix(7))"]
        if let system = pr.system { lines.append("Read the wordbase entries for \(system.name) and \(pr.wordbase.files.count) files") }
        lines.append("Wrote wordbase/prs/\(pr.number)/: pr.md, code-path.json, diagrams.json, files.json, notes.jsonl")
        if let by = pr.header.by { lines.append("Prepared by \(by)") }
        return lines
    }
}

/// Chips above the input, the input (Return sends, Option-Return adds a line) and Send.
struct SessionComposer: View {
    @Environment(ViewerStore.self) private var store
    let session: ViewerSession
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var session = session
        VStack(alignment: .leading, spacing: 6) {
            if !session.chips.isEmpty {
                ChipFlow(chips: session.chips) { index in session.removeChip(at: index) }
            }
            TextField("Ask about the selection, a file, a symbol or a diagram box", text: $session.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...6)
                .focused($focused)
                .onSubmit(send)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: .rect(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.viewerRule) }
            HStack(alignment: .firstTextBaseline) {
                Text("⌘> asks about the selection or the focused file, step, box or note. Right-click works too.")
                    .font(ViewerFonts.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                Button("Send", action: send)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(session.isBusy || (session.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && session.chips.isEmpty))
            }
        }
        .padding(Theme.inset)
        .onChange(of: session.chips.count) { old, new in if new > old { focused = true } }
    }

    private func send() { Task { await store.send(session) } }
}

/// Chips in rows; with `remove`, each carries an ×.
struct ChipFlow: View {
    let chips: [Chip]
    var remove: ((Int) -> Void)?

    var body: some View {
        ViewerFlowLayout(spacing: 4) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                HStack(spacing: 3) {
                    Text(chip.label).font(ViewerFonts.mono).lineLimit(1).truncationMode(.middle)
                    if let remove {
                        Button("Remove \(chip.label)", systemImage: "xmark") { remove(index) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).font(.system(size: 8, weight: .bold))
                    }
                }
                .foregroundStyle(Color.viewerAccent)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.viewerAccentSoft, in: .rect(cornerRadius: 4))
                .help(chip.path.map { "\($0)\(chip.lines.map { ":\($0.lowerBound)-\($0.upperBound)" } ?? "") at \(chip.commit.prefix(7))" } ?? chip.label)
            }
        }
    }
}

/// Wraps its children into rows.
struct ViewerFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            if !row.indices.isEmpty, row.width + spacing + itemWidth > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

/// The closing turn's proposals: drop any with ×; Done keeps the rest.
struct MemoriesView: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window
    let session: ViewerSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("The session proposes these notes for the wordbase").font(.headline)
                Text("Press × to drop a note. The rest are kept when you press Done, open another session or close the window.")
                    .font(ViewerFonts.meta).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if session.phase == .closing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("The session is writing its notes…").font(ViewerFonts.meta).foregroundStyle(.secondary)
                    }
                } else if session.memories.isEmpty {
                    Text(session.lastError.map { "The closing turn failed: \($0)" } ?? "No notes to keep.")
                        .font(ViewerFonts.summary).foregroundStyle(.secondary)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.background, in: .rect(cornerRadius: 6))
                }
                ForEach(session.memories) { memory in
                    HStack(alignment: .top, spacing: 6) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(memory.target).font(ViewerFonts.mono).foregroundStyle(Color.viewerAccent)
                            Text(viewerInline(memory.text)).font(ViewerFonts.summary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Button("Drop This Note", systemImage: "xmark") { store.dropMemory(memory, from: session) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(.background, in: .rect(cornerRadius: 6))
                    .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(Color.viewerRule) }
                }
                Button("Done") {
                    Task {
                        await store.keepMemories(session, reason: "added to the wordbase")
                        window.isPanelPresented = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(session.phase == .closing)
            }
            .padding(10)
            .background(Color(red: 0xf5 / 255, green: 0xf8 / 255, blue: 0xfe / 255), in: .rect(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(red: 0xc4 / 255, green: 0xd5 / 255, blue: 0xf1 / 255)) }
            .padding(Theme.inset)
        }
    }
}

/// The slim strip at the window's right edge while the panel is hidden.
struct OpenSessionStrip: View {
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        Button { window.isPanelPresented = true } label: {
            Text("Open PR session")
                .font(ViewerFonts.meta.weight(.medium))
                .foregroundStyle(Color.viewerAccent)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 28, height: 140)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 12)
        .background(.background)
        .overlay(alignment: .leading) { Divider() }
        .help("Open the PR session panel (⌥⌘I)")
    }
}
