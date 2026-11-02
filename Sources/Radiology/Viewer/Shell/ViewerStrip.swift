import AppKit
import SwiftUI
import ViewerCore

/// What a strip card's content wants at full size: a diagram's drawing with its labels at the
/// base sizes, or a fixed size for cards that are not diagrams.
struct StripNeed: Equatable, Sendable {
    var width: CGFloat
    var height: CGFloat
    /// A card that keeps its width when the strip is short of room: only drawings shrink.
    var isFixed = false

    /// A laid-out diagram's drawing at full size; a placeholder while it lays out.
    static func diagram(_ phase: DiagramLayoutPhase?) -> StripNeed {
        guard let layout = phase?.result else { return StripNeed(width: 360, height: 120) }
        let size = DiagramViewport.fullSize(of: layout)
        return StripNeed(width: size.width, height: size.height)
    }

    /// A card with only a short message, which wraps to a narrow column.
    static let message = StripNeed(width: 150, height: 0, isFixed: true)
}

/// How the strip divides its width and how tall it is (DESIGN.md §2: one row of three cards).
///
/// The two maps take the width their drawings want at full size, and the description card
/// takes the rest, down to `descriptionMinimum` (a fifth of the strip, 220 to 300 points).
/// When there is not that much room, the maps share what is left in proportion and their
/// text shrinks, never below
/// `DiagramViewport.legibleScale`; past that a map scrolls inside its card. The strip is as
/// tall as the taller map as drawn, between `minimumContent` and `maximumContent`.
enum StripPlan {
    static let gap: CGFloat = 8
    static let horizontalInset: CGFloat = 12
    static let verticalInset: CGFloat = 8
    /// At least about 32 characters of body text, so the description stays a readable column.
    static func descriptionMinimum(width: CGFloat) -> CGFloat { min(300, max(220, width * 0.2)) }
    /// Room for four lines of the description's sentence and its More link.
    static let minimumContent: CGFloat = 92
    /// The strip never takes more than this for its drawings; taller maps scroll.
    static let maximumContent: CGFloat = 176

    struct Result: Equatable {
        var description: CGFloat
        var cards: [CGFloat]
        var content: CGFloat
    }

    static func plan(width: CGFloat, needs: [StripNeed]) -> Result {
        let padding = ViewerCardMetrics.padding * 2
        let available = max(0, width - gap * CGFloat(needs.count))
        let wants = needs.map { $0.width + padding }
        let total = wants.reduce(0, +)
        var cards = wants
        var description = available - total
        let minimum = descriptionMinimum(width: width)
        if description < minimum {
            description = min(minimum, available)
            let fixed = zip(wants, needs).filter { $0.1.isFixed }.map(\.0).reduce(0, +)
            let scalable = total - fixed
            let room = max(0, available - description - fixed)
            cards = zip(wants, needs).map { want, need in
                need.isFixed ? want : (scalable > 0 ? want * room / scalable : 0)
            }
        }
        let heights = zip(cards, needs).map { card, need -> CGFloat in
            guard need.width > 0 else { return need.height }
            let zoom = max(DiagramViewport.legibleScale, min(DiagramViewport.fullScale, (card - padding) / need.width))
            return (need.height * zoom).rounded(.up)
        }
        let content = min(maximumContent, max(minimumContent, heights.max() ?? 0))
        return Result(description: description.rounded(.down), cards: cards.map { $0.rounded(.down) }, content: content)
    }

    /// The cards' height for `content` points of drawing: padding, the header line and its gap.
    static func cardHeight(content: CGFloat) -> CGFloat {
        ViewerCardMetrics.padding * 2 + headerHeight + ViewerCardMetrics.spacing + content
    }

    /// One line of the caption-sized card header.
    static let headerHeight: CGFloat = {
        let font = NSFont.preferredFont(forTextStyle: .caption1)
        return ceil(NSLayoutManager().defaultLineHeight(for: font))
    }()
}

/// The strip's row: a description card and two cards sized by `StripPlan`.
struct StripRow<Description: View, Middle: View, Trailing: View>: View {
    let needs: [StripNeed]
    @ViewBuilder var description: Description
    @ViewBuilder var middle: Middle
    @ViewBuilder var trailing: Trailing

    @State private var width: CGFloat = 0

    var body: some View {
        let plan = StripPlan.plan(width: width, needs: needs)
        HStack(alignment: .top, spacing: StripPlan.gap) {
            description.frame(width: plan.description)
            middle.frame(width: plan.cards.first ?? 0)
            trailing.frame(width: plan.cards.last ?? 0)
        }
        .frame(height: StripPlan.cardHeight(content: plan.content))
        // minWidth makes the frame take the offered width whatever the cards ask for, so the
        // measured width follows the window as it shrinks.
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.horizontal, StripPlan.horizontalInset)
        .padding(.vertical, StripPlan.verticalInset)
        .background(Color.viewerBackground)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The strip of three cards over the work area during PR review (DESIGN.md §2): the PR
/// description with its layers, the "In Marin" subsystem map, and the "Inside this PR" map with
/// its step diagrams.
struct ViewerStrip: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        let shownMap: DiagramKey = window.zoomedStep.map(DiagramKey.step) ?? .pr
        let systemNeed = store.diagram(.system) == nil ? StripNeed.message : .diagram(store.layouts[.system])
        StripRow(needs: [systemNeed, .diagram(store.layouts[shownMap])]) {
            PRDescriptionCard()
        } middle: {
            SystemMapCard()
        } trailing: {
            PRMapCard()
        }
    }
}

/// A description in layers inside a strip card: the sentence, More for the paragraph, Full
/// description for the rest, Less.
struct LayeredCardText: View {
    let layers: Layers
    @Binding var level: Int

    var body: some View {
        let maximum = layers.l3?.isEmpty == false ? 3 : (layers.l2?.isEmpty == false ? 2 : 1)
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
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
                        level = level < maximum ? level + 1 : 1
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

/// "Pull request": the PR's layered description.
struct PRDescriptionCard: View {
    @Environment(ViewerStore.self) private var store
    @Environment(ViewerWindowModel.self) private var window

    var body: some View {
        if let pr = store.pr {
            @Bindable var window = window
            ViewerCard {
                CardHeader(title: "Pull request", hint: "prepared \(Self.day(pr.header.preparedAt))")
            } content: {
                LayeredCardText(layers: pr.header.layers, level: $window.descriptionLevel)
            }
            .help("Prepared \(Self.day(pr.header.preparedAt)), before your review")
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
                .lineLimit(1).layoutPriority(1)
            Spacer(minLength: 4)
            if let hint {
                Text(hint).font(ViewerFonts.meta).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
            }
        }
        .frame(height: StripPlan.headerHeight)
        .accessibilityElement(children: .combine)
    }
}

/// A card's quiet one-line message, centred in its content.
struct CardMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(ViewerFonts.meta).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if let diagram = store.diagram(.system) {
                let changed = store.pr?.changedPaths ?? []
                let system = store.pr?.system?.name
                let sources = Dictionary(diagram.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                DiagramCard(phase: store.layouts[.system], style: { node in
                    let mark = sources[node.id].map { SystemNodeMark.mark($0, system: system, changed: changed) }
                        ?? SystemNodeMark.mark(id: node.id, paths: node.paths, system: system, changed: changed)
                    return DiagramNodeStyle(tone: Self.tone(mark))
                }, onTap: { node in
                    window.lastAskTarget = Chip(kind: .box, commit: store.pr?.head ?? "", label: "component \(node.label)")
                }, onOpenLarger: { window.enlargedDiagram = .system }) { node in
                    Button(String("Ask About \(node.label)")) {
                        store.ask(Chip(kind: .box, commit: store.pr?.head ?? "", label: "component \(node.label)"), from: window)
                    }
                    .keyboardShortcut(">", modifiers: .command)
                }
            } else {
                CardMessage(text: "No subsystem page covers this PR's files.")
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
                Button("Inside this PR") { window.zoomOut() }
                    .buttonStyle(.link).font(ViewerFonts.cardTitle)
                    .help("Back to the PR map (Escape)")
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                Text(verbatim: "Step \(id): \(step.title)").font(ViewerFonts.meta.weight(.medium)).lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            .frame(height: StripPlan.headerHeight)
            .help("Click a box to open its code. Escape goes back to the PR map.")
        } else {
            CardHeader(title: "Inside this PR", hint: "double-click a box for its step")
                .help("Click a box to open its step. Double-click a box marked + to open its step diagram.")
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

/// The larger view of a diagram, with text at full size.
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
                let region = DiagramViewport.content(of: layout)
                // Full-size text, a little larger when the drawing is small.
                let zoom = 1.15 / max(CGFloat(layout.scale), 0.01)
                ScrollView([.horizontal, .vertical]) {
                    DiagramCanvas(layout: layout, region: region, zoom: zoom, style: { node in
                        DiagramNodeStyle(isCode: node.at != nil && key != .pr, hasDiagram: key == .pr && store.hasStepDiagram(node.step))
                    }, onTap: { node in
                        if let at = node.at, key != .pr { store.reveal(path: at.path, function: at.function); dismiss() }
                        else if let step = node.step { store.focus(step: step) }
                    }) { node in
                        DiagramBoxMenu(node: node, key: key)
                    }
                    .padding(8)
                }
                .frame(minWidth: 520, idealWidth: min(1200, region.width * zoom + 40), minHeight: 220,
                       idealHeight: min(720, region.height * zoom + 40))
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
