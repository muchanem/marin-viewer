import SwiftUI
import ViewerCore

/// Inline Markdown (`code`, *emphasis*) for one-line descriptions.
func viewerInline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
}

/// The Code path tab: numbered steps with title and one-sentence description. Clicking a step
/// shows it By step; a step a session's reorder moved carries a tag.
struct ViewerCodePathSidebar: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        List {
            ForEach(store.orderedSteps, id: \.id) { step in
                let selected = store.mode == .byStep && store.focusedStepID == step.id
                ViewerStepRow(step: step, isSelected: selected, isMoved: store.movedSteps.contains(step.id))
                    .contentShape(.rect)
                    .onTapGesture {
                        store.focus(step: step.id)
                        window.lastAskTarget = ChipFactory.step(step, commit: store.pr?.head ?? "")
                    }
                    .listRowBackground(selected ? Color.viewerAccentSoft : Color.clear)
                    .contextMenu { ViewerStepMenu(step: step) }
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .listStyle(.sidebar)
    }
}

struct ViewerStepRow: View {
    let step: PRStep
    var isSelected = false
    var isMoved = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.spacing) {
            Text(step.id, format: .number.grouping(.never))
                .font(ViewerFonts.meta.monospacedDigit().weight(.semibold))
                .foregroundStyle(isSelected ? Color.viewerAccent : .secondary)
                .frame(minWidth: 14, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(step.title).font(ViewerFonts.stepTitle)
                        .foregroundStyle(isSelected ? Color.viewerAccent : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if isMoved {
                        ViewerPill(text: "moved by session", fill: .viewerNoteSoft, ink: .viewerNote)
                    }
                }
                Text(viewerInline(step.l1)).font(ViewerFonts.meta).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

/// A step's menu: ask about it, open its diagram.
struct ViewerStepMenu: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window
    let step: PRStep

    var body: some View {
        Button(String("Ask About Step \(step.id)")) { store.ask(ChipFactory.step(step, commit: store.pr?.head ?? ""), from: window) }
            .keyboardShortcut(">", modifiers: .command)
        Button(String("Show Step \(step.id)")) { store.focus(step: step.id) }
        if store.hasStepDiagram(step.id) {
            Button("Open Step Diagram") { window.zoomedStep = step.id; store.focus(step: step.id) }
        }
    }
}

/// The Changes tab in PR review: Radiology's rows with a status letter and a draft-note dot.
struct ViewerChangesView: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        let rows = store.visibleChanges
        let current = store.mode == .byFile ? store.revealRequest?.path : nil
        let drafts = store.draftNotePaths
        List(rows) { change in
            ReviewChangeRow(change: change, isSelected: current == change.path, showsStatusLetter: true,
                            hasDraftNote: drafts.contains(change.path))
                .contentShape(.rect)
                .onTapGesture {
                    store.open(path: change.path)
                    window.lastAskTarget = ChipFactory.file(change.path, commit: store.pr?.head ?? "", shortener: store.shortener)
                }
                .help(change.path)
                .listRowBackground(Color.accentColor.opacity(current == change.path ? 0.08 : 0))
                .contextMenu { ViewerFileMenu(path: change.path) }
        }
        .listStyle(.sidebar)
    }
}

/// The Files tab in PR review: the focused tree (see `FocusedTree`).
struct ViewerFocusedFilesView: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window
    @State private var toggled: Set<String> = []

    var body: some View {
        if let tree = store.focusedTree(toggled: toggled) {
            List(tree.rows) { row in
                rowView(row)
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 8))
            }
            .listStyle(.sidebar)
        } else {
            ContentUnavailableView("No Subsystem", systemImage: "folder",
                                   description: Text("No wordbase system page covers this PR's changes."))
        }
    }

    @ViewBuilder private func rowView(_ row: FocusedTree.Row) -> some View {
        switch row {
        case .root(let path):
            Text(path).font(ViewerFonts.meta.weight(.semibold)).foregroundStyle(.secondary)
        case .directory(let key, let label, let depth, let count, let isOpen):
            Button { toggle(key) } label: {
                HStack(spacing: 4) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(Theme.Fonts.disclosure)
                        .foregroundStyle(.secondary).frame(width: 10)
                    Text(verbatim: "\(label)/").font(ViewerFonts.body.weight(.medium))
                    Spacer(minLength: 4)
                    Text(verbatim: "\(count) changed").font(ViewerFonts.meta).foregroundStyle(.secondary)
                }
                .padding(.leading, CGFloat(depth) * 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label), \(count) changed, \(isOpen ? "expanded" : "collapsed")")
        case .file(let file, let depth):
            fileRow(file, label: file.name).padding(.leading, 14 + CGFloat(depth) * 6)
        case .unchangedToggle(let key, let depth, let count, let isOpen):
            Button(isOpen ? "hide unchanged" : "+ \(count) unchanged") { toggle(key) }
                .buttonStyle(.plain).font(ViewerFonts.meta).foregroundStyle(.secondary)
                .padding(.leading, 14 + CGFloat(depth) * 6)
        case .quietFile(let path, let name, let depth):
            Text(name).font(ViewerFonts.body).foregroundStyle(.secondary)
                .padding(.leading, 14 + CGFloat(depth) * 6)
                .contentShape(.rect)
                .onTapGesture { store.open(path: path) }
                .contextMenu { ViewerFileMenu(path: path) }
        case .unchangedFolders(let count, let names):
            Text(verbatim: "+ \(count) unchanged \(count == 1 ? "folder" : "folders") (\(names.map { URL(filePath: $0).lastPathComponent }.joined(separator: ", ")))")
                .font(ViewerFonts.meta).foregroundStyle(.secondary).lineLimit(2)
                .help(names.joined(separator: ", "))
        case .elsewhere(let count):
            HStack {
                Text("Elsewhere").font(ViewerFonts.body.weight(.medium))
                Spacer(minLength: 4)
                Text(verbatim: "\(count) changed").font(ViewerFonts.meta).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        case .elsewhereFile(let file):
            fileRow(file, label: file.path, quiet: true).padding(.leading, 14)
        }
    }

    private func fileRow(_ file: FocusedTree.FileRow, label: String, quiet: Bool = false) -> some View {
        let current = store.mode == .byFile && store.revealRequest?.path == file.path
        return HStack(spacing: 4) {
            if file.hasDraftNote {
                Circle().fill(Color.viewerNote).frame(width: 6, height: 6).accessibilityLabel("Draft review note")
            }
            Text(label).font(ViewerFonts.body).foregroundStyle(quiet ? .secondary : .primary)
                .fontWeight(current ? .semibold : .regular)
                .lineLimit(1).truncationMode(.middle)
            ForEach(file.steps, id: \.self) { step in
                Text(verbatim: "\(step)").font(ViewerFonts.pill.monospacedDigit()).foregroundStyle(Color.viewerAccent)
                    .padding(.horizontal, 4).background(Color.viewerAccentSoft, in: .rect(cornerRadius: 3))
                    .help("Code path step \(step)")
            }
            Spacer(minLength: 4)
            if let additions = file.additions, let deletions = file.deletions {
                Text(verbatim: "+\(additions) −\(deletions)").font(ViewerFonts.meta.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            store.open(path: file.path)
            window.lastAskTarget = ChipFactory.file(file.path, commit: store.pr?.head ?? "", shortener: store.shortener)
        }
        .help(file.path)
        .contextMenu { ViewerFileMenu(path: file.path) }
    }

    private func toggle(_ key: String) {
        if toggled.contains(key) { toggled.remove(key) } else { toggled.insert(key) }
    }
}

/// Sidebar footers in PR review, as in the demo.
struct ViewerSidebarFooter: View {
    @Environment(ViewerStore.self) private var store
    let mode: BrowserMode
    let searchMatches: Int

    var body: some View {
        @Bindable var store = store
        HStack(spacing: Theme.spacing) {
            Text(text).font(Theme.Fonts.meta).foregroundStyle(.secondary).lineLimit(2)
            Spacer(minLength: 0)
            if mode == .changes {
                Toggle("Hide tests", isOn: $store.hidesTests).toggleStyle(.checkbox).font(Theme.Fonts.meta)
                    .fixedSize()
            }
        }
        .padding(Theme.inset)
    }

    var text: String { store.footer(for: mode, searchMatches: searchMatches) }
}

extension ViewerStore {
    var visibleChanges: [FileChange] {
        guard let pr else { return [] }
        return hidesTests ? pr.changes.filter { !TestPathClassifier.isTestPath($0.path) } : pr.changes
    }

    /// Code path steps whose excerpts show each path, for the tree's badges.
    var stepsByPath: [String: [Int]] {
        var result: [String: [Int]] = [:]
        for step in pr?.wordbase.codePath ?? [] {
            for path in Set(step.excerpts.map(\.path)) { result[path, default: []].append(step.id) }
        }
        return result.mapValues { $0.sorted() }
    }

    func focusedTree(toggled: Set<String>) -> FocusedTree? {
        guard let pr, let root = pr.system?.rootDirectory else { return nil }
        return FocusedTree(root: root, headFiles: pr.headFiles, changes: pr.changes, stepsByPath: stepsByPath,
                           draftPaths: draftNotePaths, toggled: toggled)
    }

    /// "8 steps · prepared before your review", "21 of 30 files · tests hidden", and so on.
    func footer(for mode: BrowserMode, searchMatches: Int) -> String {
        guard let pr else { return "" }
        switch mode {
        case .steps:
            let count = pr.wordbase.codePath.count
            return "\(count) \(count == 1 ? "step" : "steps") · prepared before your review"
        case .changes:
            let visible = visibleChanges.count
            return "\(visible) of \(pr.changes.count) files" + (hidesTests ? " · tests hidden" : "")
        case .files:
            return "Changed files first · numbers are code path steps"
        case .search:
            return searchMatches > 0 ? "\(searchMatches) matches · ripgrep over the whole checkout" : "ripgrep over the whole checkout"
        case .codePaths:
            return ""
        }
    }
}
