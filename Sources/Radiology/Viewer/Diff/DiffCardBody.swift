import AppKit
import SwiftUI
import ViewerCore

/// A card body: the gutter on the left and the code in a scroll view that
/// moves only sideways. Its height is the layout's total, so the reader's
/// own scroll view does all vertical scrolling.
final class DiffCardBodyView: NSView {
    let gutter = DiffGutterView()
    let scroll = DiffHorizontalScrollView()
    let text = DiffCodeTextView.make()
    private var content: DiffBodyContent?
    private(set) var layoutCache: DiffCardLayout?
    private var handledScrollToken: Int?

    override var isFlipped: Bool { true }

    init(model: DiffReaderModel) {
        super.init(frame: .zero)
        // Since macOS 14 a view may draw outside its bounds; the gutter must
        // not paint over the code beside it.
        clipsToBounds = true
        gutter.clipsToBounds = true
        gutter.model = model
        text.model = model
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = text
        addSubview(scroll)
        addSubview(gutter)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func apply(_ content: DiffBodyContent) {
        if self.content?.card.id != content.card.id {
            unmount()
            text.model?.mountedBodies.insert(content.card.id)
        }
        self.content = content
        needsLayout = true
        layoutContent()
    }

    /// Tells the model this body no longer shows its card, so the reader scrolls to the card
    /// itself before the body can centre a row in it.
    func unmount() {
        if let id = content?.card.id { text.model?.mountedBodies.remove(id) }
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    private func layoutContent() {
        guard let content else { return }
        let width = max(bounds.width, 1)
        let layout = content.layout(width: width)
        layoutCache = layout
        let gutterWidth = content.gutterWidth
        gutter.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: layout.totalHeight)
        scroll.frame = NSRect(x: gutterWidth, y: 0, width: max(0, width - gutterWidth), height: layout.totalHeight)
        text.apply(content, layout: layout)
        text.frame = NSRect(x: 0, y: 0, width: max(scroll.contentSize.width, text.contentWidth), height: layout.totalHeight)
        gutter.codeBaseline = measuredBaseline(layout: layout) ?? gutter.codeBaseline
        gutter.apply(content, layout: layout)
    }

    /// Where TextKit put the baseline of the first code row, so the gutter's
    /// numbers share a baseline with the code.
    private func measuredBaseline(layout: DiffCardLayout) -> CGFloat? {
        guard let content, let manager = text.layoutManager,
              let index = content.rows.lines.firstIndex(where: { $0.row != nil }),
              let row = content.rows.lines[index].row, !content.diffRows[row].text.isEmpty else { return nil }
        let character = (0..<index).reduce(0) { total, line in
            total + ((content.rows.lines[line].row.map { content.diffRows[$0].text as NSString }?.length ?? 0) + 1)
        }
        let glyph = manager.glyphIndexForCharacter(at: character)
        guard glyph < manager.numberOfGlyphs else { return nil }
        let fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        return fragment.minY - layout.tops[index] + manager.location(forGlyphAt: glyph).y
    }

    // MARK: - Scrolling to a row

    /// Centres a row in the reader's scroll view and flashes it.
    func scroll(to target: DiffReaderModel.ScrollTarget, model: DiffReaderModel) {
        guard handledScrollToken != target.token, let row = target.row else { return }
        handledScrollToken = target.token
        DispatchQueue.main.async { [weak self, weak model] in
            guard let self else { return }
            self.layoutSubtreeIfNeeded()
            guard let content = self.content, let layout = self.layoutCache,
                  let index = content.rows.lineIndex(ofRow: row) else { return }
            let rect = layout.rect(ofLine: index, width: self.bounds.width)
            if let outer = self.enclosingScrollView, let document = outer.documentView {
                let inDocument = self.convert(rect, to: document)
                let clip = outer.contentView
                let maxY = max(0, document.bounds.height - clip.bounds.height)
                let y = min(maxY, max(0, inDocument.midY - clip.bounds.height / 2))
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
                outer.reflectScrolledClipView(clip)            } else {
                self.scrollToVisible(rect)
            }
            if target.flash { self.text.flash(line: index) }
            model?.scrollTargetHandled(target)
        }
    }
}

/// Scrolls sideways only and hands vertical wheel and trackpad movement to
/// the reader's scroll view, so a card never traps the page.
final class DiffHorizontalScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

/// SwiftUI's handle on a card body.
struct DiffCardBody: NSViewRepresentable {
    let model: DiffReaderModel
    let content: DiffBodyContent
    let scrollTarget: DiffReaderModel.ScrollTarget?

    func makeNSView(context: Context) -> DiffCardBodyView {
        DiffCardBodyView(model: model)
    }

    func updateNSView(_ view: DiffCardBodyView, context: Context) {
        view.apply(content)
        if let scrollTarget, scrollTarget.cardID == content.card.id { view.scroll(to: scrollTarget, model: model) }
    }

    static func dismantleNSView(_ view: DiffCardBodyView, coordinator: ()) { view.unmount() }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DiffCardBodyView, context: Context) -> CGSize? {
        let width = proposal.width ?? 640
        return CGSize(width: width, height: content.layout(width: width).totalHeight)
    }
}
