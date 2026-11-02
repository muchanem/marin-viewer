import SwiftUI
import ViewerCore

/// How one box draws.
struct DiagramNodeStyle: Equatable, Sendable {
    enum Tone: Equatable, Sendable { case plain, here, touched, dimmed }
    var tone: Tone = .plain
    /// Step diagram boxes that open code: monospace label on a near-white fill.
    var isCode = false
    /// The PR map's "+": the box's step has a diagram of its own.
    var hasDiagram = false
}

/// A laid-out diagram drawn with `Canvas`, with an invisible button over every box for clicks,
/// double-clicks, context menus and accessibility.
///
/// The sidecar lays a diagram out in card coordinates and draws text at the base sizes times
/// `layout.scale`. The canvas shows `region` of those coordinates (by default the whole card)
/// magnified by `zoom`, and draws text at the base sizes times `layout.scale × zoom`, so text is
/// set at its final size and stays sharp.
struct DiagramCanvas<Menu: View>: View {
    let layout: DiagramLayoutResult
    var region: CGRect?
    var zoom: CGFloat = 1
    let style: (DiagramLayoutResult.Node) -> DiagramNodeStyle
    var onTap: (DiagramLayoutResult.Node) -> Void = { _ in }
    var onDoubleTap: ((DiagramLayoutResult.Node) -> Void)?
    @ViewBuilder var menu: (DiagramLayoutResult.Node) -> Menu

    private var shown: CGRect { region ?? CGRect(x: 0, y: 0, width: layout.width, height: layout.height) }

    var body: some View {
        let shown = shown
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(in: &context) }
                .accessibilityHidden(true)
            ForEach(layout.nodes) { node in
                hitArea(node, in: shown)
            }
        }
        .frame(width: shown.width * zoom, height: shown.height * zoom, alignment: .topLeading)
    }

    /// Card coordinates to view coordinates.
    private func map(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - shown.minX) * zoom, y: (point.y - shown.minY) * zoom)
    }

    private func map(_ rect: CGRect) -> CGRect {
        CGRect(origin: map(rect.origin), size: CGSize(width: rect.width * zoom, height: rect.height * zoom))
    }

    private func hitArea(_ node: DiagramLayoutResult.Node, in shown: CGRect) -> some View {
        let rect = map(node.rect)
        return Rectangle()
            .fill(Color.clear)
            .contentShape(.rect(cornerRadius: 5))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .onTapGesture { onTap(node) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap?(node) })
            .contextMenu { menu(node) }
            .help([node.label, node.sub].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n"))
            .accessibilityElement()
            .accessibilityLabel([node.label, node.sub].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap(node) }
    }

    private func draw(in context: inout GraphicsContext) {
        // Text scale on screen: the sidecar's fit times this view's zoom.
        let text = CGFloat(layout.scale) * zoom
        for group in layout.groups {
            let path = Path(roundedRect: map(group.rect), cornerRadius: 8 * text)
            context.fill(path, with: .color(.diagramGroupFill))
            context.stroke(path, with: .color(.diagramStroke), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            let label = Text(group.label).font(.system(size: DiagramMetrics.groupLabelSize * text)).foregroundColor(.viewerMuted)
            let box = map(group.labelBox.rect)
            context.draw(label, at: CGPoint(x: box.minX, y: box.midY), anchor: .leading)
        }
        for edge in layout.edges {
            let points = edge.cgPoints.map(map)
            guard points.count >= 2 else { continue }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(.diagramEdge), lineWidth: 1)
            context.fill(arrowhead(from: points[points.count - 2], to: points[points.count - 1], size: 5 * max(text, 0.8)),
                         with: .color(.diagramEdge))
        }
        for node in layout.nodes {
            drawNode(node, style: style(node), in: &context, text: text)
        }
        // Labels last, so a label that still touches a box stays readable.
        for edge in layout.edges {
            guard let label = edge.label, let labelBox = edge.labelBox else { continue }
            let box = map(labelBox.rect)
            let words = Text(verbatim: label).font(.system(size: DiagramMetrics.edgeLabelSize * text)).foregroundColor(.viewerMuted)
            context.fill(Path(roundedRect: box.insetBy(dx: -1, dy: 0), cornerRadius: 2), with: .color(.white.opacity(0.85)))
            context.draw(words, at: CGPoint(x: box.midX, y: box.midY), anchor: .center)
        }
    }

    private func drawNode(_ node: DiagramLayoutResult.Node, style: DiagramNodeStyle, in context: inout GraphicsContext, text: CGFloat) {
        let rect = map(node.rect)
        let path = Path(roundedRect: rect, cornerRadius: 5 * text)
        let (fill, stroke, width): (Color, Color, CGFloat) = switch style.tone {
        case .here: (.viewerAccentSoft, .viewerAccent, 1.5)
        case .touched: (.diagramTouchedFill, .viewerNote, 1.5)
        case .dimmed: (.viewerSoft, .viewerRule, 1)
        case .plain: (style.isCode ? .diagramCodeFill : .white, .diagramStroke, style.hasDiagram ? 1.5 : 1)
        }
        context.fill(path, with: .color(fill))
        context.stroke(path, with: .color(stroke), lineWidth: width)
        let ink: Color = style.tone == .dimmed ? .viewerMuted : .viewerInk
        let labelFont: Font = style.isCode
            ? .system(size: DiagramMetrics.codeLabelSize * text, design: .monospaced)
            : .system(size: DiagramMetrics.labelSize * text)
        let inset = 8 * text
        let hasSub = !(node.sub ?? "").isEmpty
        let labelY = hasSub ? rect.minY + 10.5 * text : rect.midY
        context.draw(Text(node.label).font(labelFont).foregroundColor(ink),
                     at: CGPoint(x: rect.minX + inset, y: labelY), anchor: .leading)
        if hasSub, let sub = node.sub {
            context.draw(Text(sub).font(.system(size: DiagramMetrics.subSize * text)).foregroundColor(.viewerMuted),
                         at: CGPoint(x: rect.minX + inset, y: rect.minY + 23 * text), anchor: .leading)
        }
        if style.hasDiagram {
            context.draw(Text("+").font(.system(size: 9 * max(text, 0.9), weight: .semibold)).foregroundColor(.viewerAccent),
                         at: CGPoint(x: rect.maxX - 7 * text, y: rect.minY + 8 * text), anchor: .center)
        }
    }

    private func arrowhead(from: CGPoint, to: CGPoint, size: CGFloat) -> Path {
        let angle = atan2(to.y - from.y, to.x - from.x)
        var path = Path()
        path.move(to: to)
        path.addLine(to: CGPoint(x: to.x - size * cos(angle - .pi / 7), y: to.y - size * sin(angle - .pi / 7)))
        path.addLine(to: CGPoint(x: to.x - size * cos(angle + .pi / 7), y: to.y - size * sin(angle + .pi / 7)))
        path.closeSubpath()
        return path
    }
}

/// How large a laid-out diagram draws in the strip. The sidecar centres every diagram in a
/// 460×196 card, which leaves margins the strip has no room for, so the strip shows only the
/// drawing (`content`) and sizes it by its text: full size is the base type sizes (labels
/// 10.5 pt). The strip plans its height for labels of at least `legibleScale` of that, and a
/// map shrinks to `smallestScale` before it scrolls.
enum DiagramViewport {
    /// The text size the strip plans for, as a fraction of the base sizes: labels at 9.5 pt.
    static let legibleScale: CGFloat = 0.9
    /// The smallest text a map takes to fit its card instead of scrolling: labels at 8.9 pt.
    static let smallestScale: CGFloat = 0.85
    /// The largest: the base sizes themselves.
    static let fullScale: CGFloat = 1

    /// The drawn part of the card: boxes, groups, edges and labels, with a little air.
    static func content(of layout: DiagramLayoutResult) -> CGRect {
        var rects = layout.nodes.map(\.rect) + layout.groups.map(\.rect) + layout.groups.map(\.labelBox.rect)
        for edge in layout.edges {
            rects += edge.cgPoints.map { CGRect(origin: $0, size: .zero) }
            if let box = edge.labelBox { rects.append(box.rect) }
        }
        guard let first = rects.first else { return CGRect(x: 0, y: 0, width: layout.width, height: layout.height) }
        let union = rects.dropFirst().reduce(first) { $0.union($1) }
        let air = 4 * CGFloat(layout.scale)
        return union.insetBy(dx: -air, dy: -air).intersection(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
    }

    /// The content's size with text at full size, in points.
    static func fullSize(of layout: DiagramLayoutResult) -> CGSize {
        let content = content(of: layout)
        let scale = max(CGFloat(layout.scale), 0.01)
        return CGSize(width: content.width / scale, height: content.height / scale)
    }

    /// The zoom that fits `content` into `available`, kept between legible and full-size text.
    static func zoom(for layout: DiagramLayoutResult, in available: CGSize) -> CGFloat {
        let content = content(of: layout)
        let scale = max(CGFloat(layout.scale), 0.01)
        guard content.width > 0, content.height > 0 else { return 1 }
        let fit = min(available.width / content.width, available.height / content.height)
        return min(max(fit, smallestScale / scale), fullScale / scale)
    }
}

/// A diagram in its strip card, sized by `DiagramViewport`: it fits the card when it can at
/// legible size, and scrolls inside the card when it cannot, with "Open Larger".
struct DiagramCard<Menu: View>: View {
    let phase: DiagramLayoutPhase?
    let style: (DiagramLayoutResult.Node) -> DiagramNodeStyle
    var onTap: (DiagramLayoutResult.Node) -> Void = { _ in }
    var onDoubleTap: ((DiagramLayoutResult.Node) -> Void)?
    var onOpenLarger: (() -> Void)?
    @ViewBuilder var menu: (DiagramLayoutResult.Node) -> Menu

    var body: some View {
        switch phase {
        case .ready(let layout):
            GeometryReader { proxy in
                let region = DiagramViewport.content(of: layout)
                let zoom = DiagramViewport.zoom(for: layout, in: proxy.size)
                let size = CGSize(width: region.width * zoom, height: region.height * zoom)
                let overflows = size.width > proxy.size.width + 0.5 || size.height > proxy.size.height + 0.5
                let canvas = DiagramCanvas(layout: layout, region: region, zoom: zoom, style: style, onTap: onTap,
                                           onDoubleTap: onDoubleTap, menu: menu)
                if overflows {
                    ScrollView([.horizontal, .vertical]) { canvas }
                        .scrollIndicators(.automatic)
                        .overlay(alignment: .bottomTrailing) { openLarger }
                } else {
                    canvas.frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
        case .failed(let message):
            Text(verbatim: "The diagram could not be laid out: \(message)")
                .font(ViewerFonts.meta).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading, nil:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var openLarger: some View {
        if let onOpenLarger {
            Button("Open Larger", systemImage: "arrow.up.left.and.arrow.down.right", action: onOpenLarger)
                .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                .padding(4).background(.regularMaterial, in: .rect(cornerRadius: 5))
                .padding(4)
                .help("This diagram is larger than its card. Open it in a larger view.")
        }
    }
}
