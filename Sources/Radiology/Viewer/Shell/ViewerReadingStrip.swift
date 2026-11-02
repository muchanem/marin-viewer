import SwiftUI
import ViewerCore

/// The strip outside PR review (DESIGN.md §2): the open subsystem's page, as its description,
/// its place among Marin's packages, and its own map.
struct ViewerReadingStrip: View {
    @Environment(ViewerStore.self) private var store
    let page: SystemPage

    var body: some View {
        let mapNeed = page.diagram == nil ? StripNeed.message : .diagram(store.systemLayouts[page.name])
        StripRow(needs: [SystemPlaceCard.need(for: page), mapNeed]) {
            SystemDescriptionCard(page: page)
        } middle: {
            SystemPlaceCard(page: page)
        } trailing: {
            SystemPageMapCard(page: page)
        }
    }
}

/// The page's layered description, under the package's name.
struct SystemDescriptionCard: View {
    @Environment(ViewerStore.self) private var store
    let page: SystemPage

    var body: some View {
        @Bindable var store = store
        ViewerCard {
            CardHeader(title: page.name, hint: page.updated.map { "updated \(PRDescriptionCard.day($0))" })
        } content: {
            if let layers = page.layers {
                LayeredCardText(layers: layers, level: $store.systemDescriptionLevel)
            } else {
                CardMessage(text: "This page has no description yet.")
            }
        }
    }
}

/// "In Marin": the packages that use this one and the packages it uses. Each is a button that
/// opens that package's page in the strip.
struct SystemPlaceCard: View {
    @Environment(ViewerStore.self) private var store
    let page: SystemPage

    /// Wide enough for four short package names a row.
    static func need(for page: SystemPage) -> StripNeed {
        let rows = [page.usedBy.count, page.uses.count].filter { $0 > 0 }.map { ($0 + 3) / 4 }
        let height = rows.reduce(0) { $0 + StripPlan.headerHeight + 4 + CGFloat($1) * 26 } + CGFloat(max(0, rows.count - 1)) * 10
        return StripNeed(width: 300, height: height)
    }

    var body: some View {
        ViewerCard {
            CardHeader(title: "In Marin", hint: "click a package to open its page")
        } content: {
            if page.uses.isEmpty && page.usedBy.isEmpty {
                CardMessage(text: "No other package under lib/ uses \(page.name), and it uses none.")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !page.usedBy.isEmpty { group("Used by", page.usedBy) }
                        if !page.uses.isEmpty { group("Uses", page.uses) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.automatic)
            }
        }
    }

    private func group(_ title: String, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(ViewerFonts.meta).foregroundStyle(.secondary)
            ViewerFlowLayout(spacing: 6) {
                ForEach(names, id: \.self) { name in
                    let described = store.systemPage(named: name)
                    Button(name) { store.showSystem(named: name) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(described == nil)
                        .help(described?.layers?.l1 ?? "No page describes \(name) yet.")
                }
            }
        }
    }
}

/// The page's own map: the box holding the open file is highlighted, and a box that stands for
/// other packages opens their page.
struct SystemPageMapCard: View {
    @Environment(ViewerStore.self) private var store
    let page: SystemPage

    var body: some View {
        ViewerCard {
            CardHeader(title: "Map", hint: page.name == store.readingSystemOfOpenFile ? "the open file is highlighted" : nil)
        } content: {
            if let diagram = page.diagram {
                let marks = SystemNodeMark.readingMarks(diagram.nodes, system: page.name,
                                                       openPath: page.name == store.readingSystemOfOpenFile ? store.readingPath : nil)
                let sources = Dictionary(diagram.nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                DiagramCard(phase: store.systemLayouts[page.name], style: { node in
                    DiagramNodeStyle(tone: marks[node.id] == .here ? .here : .plain)
                }, onTap: { node in
                    let others = otherSystems(sources[node.id])
                    if others.count == 1 { store.showSystem(named: others[0]) }
                }) { node in
                    ForEach(otherSystems(sources[node.id]), id: \.self) { name in
                        Button("Open \(name) Page") { store.showSystem(named: name) }
                            .disabled(store.systemPage(named: name) == nil)
                    }
                }
            } else {
                CardMessage(text: "This page has no map yet.")
            }
        }
    }

    /// The described packages a box stands for, other than this page's own.
    private func otherSystems(_ node: DiagramNode?) -> [String] {
        guard let node else { return [] }
        let names = (node.systems ?? []) + (store.systemPage(named: node.id) != nil ? [node.id] : [])
        var seen = Set<String>()
        return names.filter { $0.caseInsensitiveCompare(page.name) != .orderedSame && seen.insert($0.lowercased()).inserted }
    }
}

extension ViewerStore {
    /// The subsystem of the file open in the main reader, by name.
    var readingSystemOfOpenFile: String? {
        readingPath.flatMap { SystemPage.covering($0, in: systemPages)?.name }
    }
}
