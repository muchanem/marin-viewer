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

/// A laid-out diagram drawn with `Canvas` at the sidecar's card coordinates, with an invisible
/// button over every box for clicks, double-clicks, context menus and accessibility.
///
/// The view is `layout.width × layout.height` points; text is drawn at the base sizes times
/// `layout.scale`, the same factor the sidecar applied to box sizes measured in those fonts.
struct DiagramCanvas<Menu: View>: View {
    let layout: DiagramLayoutResult
    let style: (DiagramLayoutResult.Node) -> DiagramNodeStyle
    var onTap: (DiagramLayoutResult.Node) -> Void = { _ in }
    var onDoubleTap: ((DiagramLayoutResult.Node) -> Void)?
    @ViewBuilder var menu: (DiagramLayoutResult.Node) -> Menu

    var body: some View {
        let scale = CGFloat(layout.scale)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in draw(in: &context, scale: scale) }
                .accessibilityHidden(true)
            ForEach(layout.nodes) { node in
                hitArea(node)
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    private func hitArea(_ node: DiagramLayoutResult.Node) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(.rect(cornerRadius: 5))
            .frame(width: node.w, height: node.h)
            .offset(x: node.x, y: node.y)
            .onTapGesture { onTap(node) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onDoubleTap?(node) })
            .contextMenu { menu(node) }
            .help([node.label, node.sub].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n"))
            .accessibilityElement()
            .accessibilityLabel([node.label, node.sub].compactMap { $0 }.joined(separator: ", "))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap(node) }
    }

    private func draw(in context: inout GraphicsContext, scale: CGFloat) {
        for group in layout.groups {
            let path = Path(roundedRect: group.rect, cornerRadius: 8 * scale)
            context.fill(path, with: .color(.diagramGroupFill))
            context.stroke(path, with: .color(.diagramStroke), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            let label = Text(group.label).font(.system(size: DiagramMetrics.groupLabelSize * scale)).foregroundColor(.viewerMuted)
            context.draw(label, at: CGPoint(x: group.labelBox.x, y: group.labelBox.y + group.labelBox.h / 2), anchor: .leading)
        }
        for edge in layout.edges {
            let points = edge.cgPoints
            guard points.count >= 2 else { continue }
            var path = Path()
            path.addLines(points)
            context.stroke(path, with: .color(.diagramEdge), lineWidth: 1)
            context.fill(arrowhead(from: points[points.count - 2], to: points[points.count - 1], size: 5 * max(scale, 0.8)),
                         with: .color(.diagramEdge))
            if let label = edge.label, let box = edge.labelBox {
                let text = Text(label).font(.system(size: DiagramMetrics.edgeLabelSize * scale)).foregroundColor(.viewerMuted)
                context.fill(Path(roundedRect: box.rect.insetBy(dx: -1, dy: 0), cornerRadius: 2), with: .color(.white.opacity(0.85)))
                context.draw(text, at: CGPoint(x: box.x + box.w / 2, y: box.y + box.h / 2), anchor: .center)
            }
        }
        for node in layout.nodes {
            drawNode(node, style: style(node), in: &context, scale: scale)
        }
    }

    private func drawNode(_ node: DiagramLayoutResult.Node, style: DiagramNodeStyle, in context: inout GraphicsContext, scale: CGFloat) {
        let rect = node.rect
        let path = Path(roundedRect: rect, cornerRadius: 5 * scale)
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
            ? .system(size: DiagramMetrics.codeLabelSize * scale, design: .monospaced)
            : .system(size: DiagramMetrics.labelSize * scale)
        let inset = 8 * scale
        let hasSub = !(node.sub ?? "").isEmpty
        let labelY = hasSub ? rect.minY + 10.5 * scale : rect.midY
        context.draw(Text(node.label).font(labelFont).foregroundColor(ink),
                     at: CGPoint(x: rect.minX + inset, y: labelY), anchor: .leading)
        if hasSub, let sub = node.sub {
            context.draw(Text(sub).font(.system(size: DiagramMetrics.subSize * scale)).foregroundColor(.viewerMuted),
                         at: CGPoint(x: rect.minX + inset, y: rect.minY + 23 * scale), anchor: .leading)
        }
        if style.hasDiagram {
            context.draw(Text("+").font(.system(size: 9 * max(scale, 0.9), weight: .semibold)).foregroundColor(.viewerAccent),
                         at: CGPoint(x: rect.maxX - 7 * scale, y: rect.minY + 8 * scale), anchor: .center)
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

/// A diagram in its card: fitted to the card when it fits at its scale, scrolled when it
/// overflows (`overflow`, the natural size at the `minScale` floor), with "Open Larger".
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
            let canvas = DiagramCanvas(layout: layout, style: style, onTap: onTap, onDoubleTap: onDoubleTap, menu: menu)
            if layout.overflow {
                ScrollView([.horizontal, .vertical]) { canvas }
                    .frame(maxWidth: .infinity, maxHeight: DiagramMetrics.card.height)
                    .overlay(alignment: .bottomTrailing) {
                        if let onOpenLarger {
                            Button("Open Larger", systemImage: "arrow.up.left.and.arrow.down.right", action: onOpenLarger)
                                .labelStyle(.iconOnly).buttonStyle(.borderless).controlSize(.small)
                                .padding(4).background(.regularMaterial, in: .rect(cornerRadius: 5))
                                .padding(4)
                                .help("This diagram is larger than its card. Open it in a larger view.")
                        }
                    }
            } else {
                GeometryReader { proxy in
                    let fit = min(1, proxy.size.width / layout.width, proxy.size.height / layout.height)
                    canvas
                        .scaleEffect(fit, anchor: .topLeading)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                }
                .frame(maxWidth: layout.width, maxHeight: layout.height)
                .aspectRatio(layout.width / layout.height, contentMode: .fit)
            }
        case .failed(let message):
            Text("The diagram could not be laid out: \(message)")
                .font(ViewerFonts.meta).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading, nil:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
