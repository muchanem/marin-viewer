import AppKit
import SwiftUI
import ViewerCore

/// The strip of three cards over the work area (DESIGN.md §2): the PR description with its
/// layers, the "In Marin" subsystem map, and the "Inside this PR" map with its step diagrams.
struct ViewerStrip: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    @State private var width: CGFloat = 0

    var body: some View {
        // Column weights 1.25 : 1 : 1.2, as in the demo.
        let unit = max(0, width - Self.spacing * 2) / 3.45
        HStack(alignment: .top, spacing: Self.spacing) {
            PRDescriptionCard().frame(width: unit * 1.25)
            SystemMapCard().frame(width: unit)
            PRMapCard().frame(width: unit * 1.2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.height(diagram: diagramHeight(unit: unit)))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.viewerBackground)
        .overlay(alignment: .bottom) { Divider() }
    }

    static let spacing: CGFloat = 10

    /// The taller of the two diagrams as their cards draw them, so the strip ends where the
    /// drawings do. Until either is laid out, the card's full diagram height.
    private func diagramHeight(unit: CGFloat) -> CGFloat {
        let pr: DiagramKey = window.zoomedStep.map(DiagramKey.step) ?? .pr
        let heights = [
            Self.fittedHeight(store.layouts[.system], width: unit - ViewerCardMetrics.padding * 2),
            Self.fittedHeight(store.layouts[pr], width: unit * 1.2 - ViewerCardMetrics.padding * 2),
        ].compactMap { $0 }
        return heights.max() ?? DiagramMetrics.card.height
    }

    /// The height `DiagramCard` gives a laid-out diagram in a card `width` wide: scaled down to
    /// the width, never up, and at most the card's diagram height (an overflowing one scrolls).
    static func fittedHeight(_ phase: DiagramLayoutPhase?, width: CGFloat) -> CGFloat? {
        guard case .ready(let layout)? = phase, layout.width > 0, layout.height > 0 else { return nil }
        if layout.overflow { return DiagramMetrics.card.height }
        let scale = min(1, max(0, width) / layout.width, DiagramMetrics.card.height / layout.height)
        return (layout.height * scale).rounded(.up)
    }

    /// The cards' height for a diagram `diagram` points tall: padding, the header line, the
    /// header gap and the drawing. Never shorter than the description card's sentence and More.
    static func height(diagram: CGFloat) -> CGFloat {
        let content = max(diagram, minimumContent)
        return ViewerCardMetrics.padding * 2 + headerHeight + ViewerCardMetrics.spacing + content
    }

    /// Room for about three lines of the description's sentence and its More link.
    static let minimumContent: CGFloat = 84
    /// One line of the caption-sized card header.
    static let headerHeight: CGFloat = {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        return ceil(NSLayoutManager().defaultLineHeight(for: font))
    }()
}

/// "Pull request": one sentence, More for the paragraph, Full description for the rest, Less.
struct PRDescriptionCard: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        if let pr = store.pr {
            let layers = pr.header.layers
            let level = window.descriptionLevel
            let maximum = layers.l3?.isEmpty == false ? 3 : (layers.l2?.isEmpty == false ? 2 : 1)
            ViewerCard {
                CardHeader(title: "Pull request", hint: "prepared \(Self.day(pr.header.preparedAt)), before your review")
            } content: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(viewerInline(layers.l1)).font(ViewerFonts.body)
                        if level >= 2, let l2 = layers.l2 {
                            Text(viewerInline(l2)).font(ViewerFonts.summary).foregroundStyle(Color.viewerInk.opacity(0.9))
                        }
                        if level >= 3 {
                            ForEach(Array((layers.l3 ?? []).enumerated()), id: \.offset) { _, paragraph in
                                Text(viewerInline(paragraph)).font(ViewerFonts.summary).foregroundStyle(Color.viewerInk.opacity(0.9))
                            }
                        }
                        if maximum > 1 {
                            Button(level < maximum ? (level == 1 ? "More" : "Full description") : "Less") {
                                window.descriptionLevel = level < maximum ? level + 1 : 1
                            }
                            .buttonStyle(.link).font(ViewerFonts.meta)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    /// "2026-10-30" from an ISO timestamp.
    static func day(_ timestamp: String) -> String { String(timestamp.prefix(10)) }
}

struct CardHeader: View {
    let title: String
    var hint: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title.uppercased()).font(ViewerFonts.cardTitle).tracking(0.6).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            if let hint {
                Text(hint).font(ViewerFonts.meta).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "In Marin": the subsystem's map with the PR's subsystem highlighted and the boxes whose paths
/// the PR changes marked.
struct SystemMapCard: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        ViewerCard {
            CardHeader(title: "In Marin", hint: store.pr?.system.map { "where \($0.name) sits" })
        } content: {
            if store.diagram(.system) == nil {
                Text("No wordbase system page covers this PR's files.").font(ViewerFonts.meta).foregroundStyle(.secondary)
            } else {
                let changed = store.pr?.changedPaths ?? []
                let system = store.pr?.system?.name
                DiagramCard(phase: store.layouts[.system], style: { node in
                    DiagramNodeStyle(tone: Self.tone(SystemNodeMark.mark(id: node.id, paths: node.paths, system: system, changed: changed)))
                }, onTap: { node in
                    window.lastAskTarget = Chip(kind: .box, commit: store.pr?.head ?? "", label: "component \(node.label)")
                }, onOpenLarger: { window.enlargedDiagram = .system }) { node in
                    Button(String("Ask About \(node.label)")) {
                        store.ask(Chip(kind: .box, commit: store.pr?.head ?? "", label: "component \(node.label)"), from: window)
                    }
                    .keyboardShortcut(">", modifiers: .command)
                }
            }
        }
    }

    static func tone(_ mark: SystemNodeMark) -> DiagramNodeStyle.Tone {
        switch mark {
        case .here: .here
        case .touched: .touched
        case .dimmed: .dimmed
        case .plain: .plain
        }
    }
}

/// "Inside this PR": the PR map; double-click zooms into a step diagram, the breadcrumb or
/// Escape zooms out, and a click on a step diagram's box scrolls the main view to its code.
struct PRMapCard: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        ViewerCard {
            header
        } content: {
            if let step = window.zoomedStep {
                stepDiagram(step)
            } else {
                prMap
            }
        }
        .onKeyPress(.escape) {
            guard window.zoomedStep != nil else { return .ignored }
            window.zoomOut()
            return .handled
        }
    }

    @ViewBuilder private var header: some View {
        if let id = window.zoomedStep, let step = store.pr?.step(id) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Button("This PR") { window.zoomOut() }.buttonStyle(.link).font(ViewerFonts.meta)
                    .help("Back to the PR map (Escape)")
                Text("/").font(ViewerFonts.meta).foregroundStyle(.tertiary)
                Text(verbatim: "Step \(id): \(step.title)").font(ViewerFonts.meta.weight(.medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text("click a box to open its code").font(ViewerFonts.meta).foregroundStyle(.tertiary).lineLimit(1)
            }
        } else {
            CardHeader(title: "Inside this PR", hint: "click: open step · double-click: step diagram")
        }
    }

    private var prMap: some View {
        DiagramCard(phase: store.layouts[.pr], style: { node in
            let current = store.mode == .byStep && node.step != nil && node.step == store.focusedStepID
            return DiagramNodeStyle(tone: current ? .here : .plain, hasDiagram: store.hasStepDiagram(node.step))
        }, onTap: { node in
            window.lastAskTarget = chip(node)
            if let step = node.step { store.focus(step: step) }
        }, onDoubleTap: { node in
            if let step = node.step { store.openStepDiagram(step, in: window) }
        }, onOpenLarger: { window.enlargedDiagram = .pr }) { node in
            DiagramBoxMenu(node: node, key: .pr)
        }
    }

    private func stepDiagram(_ id: Int) -> some View {
        DiagramCard(phase: store.layouts[.step(id)], style: { node in
            DiagramNodeStyle(isCode: node.at != nil)
        }, onTap: { node in
            window.lastAskTarget = chip(node)
            store.openCode(of: node)
        }, onOpenLarger: { window.enlargedDiagram = .step(id) }) { node in
            DiagramBoxMenu(node: node, key: .step(id))
        }
    }

    private func chip(_ node: DiagramLayoutResult.Node) -> Chip {
        ChipFactory.box(label: node.label, at: node.at, commit: store.pr?.head ?? "", shortener: store.shortener)
    }
}

/// A box's menu: ask about it, open its code, go to its step, open its step diagram.
struct DiagramBoxMenu: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window
    let node: DiagramLayoutResult.Node
    let key: DiagramKey

    var body: some View {
        ForEach(DiagramBoxAction.actions(for: node, in: key, hasStepDiagram: store.hasStepDiagram), id: \.self) { action in
            if action == .ask {
                Button(action.title(label: node.label)) { perform(action) }.keyboardShortcut(">", modifiers: .command)
            } else {
                Button(action.title(label: node.label)) { perform(action) }
            }
        }
    }

    private func perform(_ action: DiagramBoxAction) {
        switch action {
        case .ask:
            store.ask(ChipFactory.box(label: node.label, at: node.at, commit: store.pr?.head ?? "", shortener: store.shortener), from: window)
        case .openCode(let at): store.reveal(path: at.path, function: at.function)
        case .openCodeInNewWindow(let path): store.openInNewWindow(path: path)
        case .goToStep(let step): store.focus(step: step)
        case .openStepDiagram(let step): store.openStepDiagram(step, in: window)
        }
    }
}

/// The larger view of a diagram that overflows its card, at twice the card's scale floor.
struct EnlargedDiagramSheet: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window
    @Environment(\.dismiss) private var dismiss
    let key: DiagramKey

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            if let layout = store.layouts[key]?.result {
                let zoom = min(1.6, 1 / max(layout.scale, 0.01))
                ScrollView([.horizontal, .vertical]) {
                    DiagramCanvas(layout: layout, style: { node in
                        DiagramNodeStyle(isCode: node.at != nil && key != .pr, hasDiagram: key == .pr && store.hasStepDiagram(node.step))
                    }, onTap: { node in
                        if let at = node.at, key != .pr { store.reveal(path: at.path, function: at.function); dismiss() }
                        else if let step = node.step { store.focus(step: step) }
                    }) { node in
                        DiagramBoxMenu(node: node, key: key)
                    }
                    .scaleEffect(zoom, anchor: .topLeading)
                    .frame(width: layout.width * zoom, height: layout.height * zoom, alignment: .topLeading)
                    .padding(8)
                }
                .frame(minWidth: 520, idealWidth: min(1100, layout.width * zoom + 40), minHeight: 260,
                       idealHeight: min(700, layout.height * zoom + 40))
            }
        }
        .padding(16)
    }

    private var title: String {
        switch key {
        case .system: "In Marin"
        case .pr: "Inside this PR"
        case .step(let id): "Step \(id): \(store.pr?.step(id)?.title ?? "")"
        }
    }
}
