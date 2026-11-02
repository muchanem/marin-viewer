import AppKit

final class LineNumberGutter: NSView {
    private weak var textView: NSTextView?
    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { true }
    var buffer: SourceBuffer?
    var fontSize = Theme.sourceFontSize
    /// Derived from the actual selection, never from a viewport/restoration row.
    var currentLine: Int {
        guard let buffer, let textView else { return 1 }
        return buffer.line(atByte: buffer.byteOffset(forUTF16: textView.selectedRange().location))
    }
    /// The last visible canonical labels, also useful for native rendering QA.
    private(set) var numberedLines: [Int] = []
    var folds: [SourceFold] = []
    var foldedIDs = Set<String>()
    /// Generic per-fold counts (Critical mode: reachable critical
    /// operations), keyed by fold id. When shown for a collapsed function
    /// they replace the hidden-line capsule; the hidden-line count stays in
    /// the tooltip and accessibility text.
    var annotations: [String: CountAnnotation] = [:]
    var showsAnnotations = false
    /// One-based source lines changed by a pull request, marked with a bar
    /// beside their line numbers; the color follows the revision.
    var changedLines: [Range<Int>] = []
    var changeRevision: ReviewRevision?
    var onToggleFold: ((SourceFold) -> Void)?
    /// Hidden test regions (Hide Tests): a collapsed disclosure and the
    /// hidden-line capsule on the header row, taking that row's fold control.
    struct TestMarker: Equatable {
        let id: Int
        let headerLine: Int
        let hiddenLineCount: Int
    }
    var testMarkers: [TestMarker] = [] {
        didSet { if testMarkers != oldValue { needsDisplay = true } }
    }
    var onToggleTestRegion: ((Int) -> Void)?
    private var testHitRects: [Int: NSRect] = [:]
    private var foldHitRects: [String: NSRect] = [:]
    private var foldTooltips: [NSView.ToolTipTag] = []
    private var foldTooltipText: [NSView.ToolTipTag: String] = [:]

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
        setAccessibilityLabel("Source line numbers and folding controls")
        setAccessibilityHelp("Click a disclosure control to collapse or expand a source region.")
    }
    required init(coder: NSCoder) { fatalError("LineNumberGutter is constructed programmatically.") }

    override func draw(_ rect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        for tag in foldTooltips { removeToolTip(tag) }
        foldTooltips.removeAll(keepingCapacity: true)
        foldTooltipText.removeAll(keepingCapacity: true)
        foldHitRects.removeAll(keepingCapacity: true)
        testHitRects.removeAll(keepingCapacity: true)
        numberedLines.removeAll(keepingCapacity: true)
        var collapsedFunctionDescriptions: [String] = []
        let testMarkersByLine = Dictionary(testMarkers.map { ($0.headerLine, $0) }, uniquingKeysWith: { first, _ in first })
        guard let text = textView, let layout = text.layoutManager,
              let container = text.textContainer, let buffer else { return }
        let visible = text.visibleRect
        let contentFrame: NSRect
        if let clip = text.enclosingScrollView?.contentView {
            contentFrame = clip.convert(clip.bounds, to: self)
        } else {
            contentFrame = bounds
        }
        let glyphs = layout.glyphRange(forBoundingRect: visible.offsetBy(dx: -text.textContainerOrigin.x, dy: -text.textContainerOrigin.y), in: container)
        // Line numbers are interface metadata, independent of source zoom.
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        let caretFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        let caretLine = currentLine
        setAccessibilityValue("Current line \(caretLine); line numbers every five lines")
        var rows: [(line: Int, y: CGFloat)] = []
        var seenLines = Set<Int>()
        layout.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, glyphRange, _ in
            guard let glyph = Self.firstVisibleGlyph(in: glyphRange, layout: layout) else { return }
            let offset = layout.characterIndexForGlyph(at: glyph)
            let line = buffer.line(atByte: buffer.byteOffset(forUTF16: offset))
            // A wrapped fragment should not repeat the canonical source number.
            guard seenLines.insert(line).inserted else { return }
            let y = rect.minY + text.textContainerOrigin.y - visible.minY + contentFrame.minY
            rows.append((line, y))
        }
        if glyphs.location + glyphs.length >= layout.numberOfGlyphs,
           buffer.text.hasSuffix("\n"), seenLines.insert(buffer.lineCount).inserted {
            rows.append((buffer.lineCount, layout.extraLineFragmentRect.minY
                         + text.textContainerOrigin.y - visible.minY + contentFrame.minY))
        }
        for (line, y) in rows {
            guard y < contentFrame.maxY, y + Theme.sourceLineHeight > contentFrame.minY else { continue }
            var numberMinX: CGFloat?
            if line.isMultiple(of: 5) || line == caretLine {
                let label = "\(line)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: line == caretLine ? caretFont : font,
                    .foregroundColor: line == caretLine ? NSColor.labelColor : NSColor.secondaryLabelColor,
                ]
                let size = label.size(withAttributes: attributes)
                let x = bounds.width - size.width - Theme.gutterInset
                numberMinX = x
                numberedLines.append(line)
                label.draw(at: NSPoint(x: x, y: y + (max(Theme.sourceLineHeight, fontSize * 1.55) - size.height) / 2), withAttributes: attributes)
            }
            if let changeRevision, Self.isChanged(line: line, in: changedLines) {
                Theme.changeBarColor(revision: changeRevision).setFill()
                NSRect(x: bounds.width - Theme.changeBarWidth - 2, y: y, width: Theme.changeBarWidth,
                       height: max(Theme.sourceLineHeight, fontSize * 1.55)).fill()
            }
            let rowHeight = max(Theme.sourceLineHeight, fontSize * 1.55)
            if let marker = testMarkersByLine[line] {
                let hitRect = NSRect(x: 0, y: y, width: Theme.foldHitWidth, height: rowHeight)
                testHitRects[marker.id] = hitRect
                drawDisclosure("▶", in: hitRect)
                let noun = marker.hiddenLineCount == 1 ? "line" : "lines"
                let description = "Test code — \(marker.hiddenLineCount) \(noun) hidden. Click to show."
                var badge = hitRect
                if marker.hiddenLineCount > 0 {
                    badge = drawCountCapsule(Self.foldCountLabel(hiddenLineCount: marker.hiddenLineCount), row: hitRect, numberMinX: numberMinX) ?? hitRect
                }
                collapsedFunctionDescriptions.append(description)
                let tag = addToolTip(hitRect.union(badge), owner: self, userData: nil)
                foldTooltips.append(tag)
                foldTooltipText[tag] = description
            } else if let fold = fold(onHeaderLine: line, buffer: buffer) {
                let collapsed = foldedIDs.contains(fold.id)
                let symbol = collapsed ? "▶" : "▼"
                let hitRect = NSRect(x: 0, y: y, width: Theme.foldHitWidth,
                                     height: max(Theme.sourceLineHeight, fontSize * 1.55))
                foldHitRects[fold.id] = hitRect
                let markerFont = NSFont.systemFont(ofSize: Theme.foldMarkerSize, weight: .medium)
                let markerSize = (symbol as NSString).size(withAttributes: [.font: markerFont])
                (symbol as NSString).draw(at: NSPoint(x: (Theme.foldHitWidth - markerSize.width) / 2,
                                                       y: y + (max(Theme.sourceLineHeight, fontSize * 1.55) - markerSize.height) / 2), withAttributes: [
                    .font: markerFont,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ])
                if collapsed, fold.kind == "function" {
                    let hidden = Self.hiddenSourceLineCount(for: fold, in: buffer)
                    let width = Self.functionMeterWidth(hiddenLineCount: hidden)
                    let meter = NSRect(x: (Theme.foldHitWidth - width) / 2,
                                       y: hitRect.maxY - 4, width: width, height: 3)
                    NSColor.secondaryLabelColor.setFill()
                    NSBezierPath(roundedRect: meter, xRadius: 1.5, yRadius: 1.5).fill()

                    let annotation = showsAnnotations ? annotations[fold.id] : nil
                    // One count lane: the hidden-line capsule, or in a mode
                    // with annotations the generic count in a rounded square
                    // with an accent stroke, so the two numbers never share
                    // a shape. The hidden-line count then lives in the
                    // tooltip and accessibility text.
                    let count = (annotation?.label ?? Self.foldCountLabel(hiddenLineCount: hidden)) as NSString
                    let countFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
                    let receded = annotation.map { $0.isProvenZero || $0.completeness == .noBody } ?? false
                    let countAttributes: [NSAttributedString.Key: Any] = [
                        .font: countFont,
                        .foregroundColor: annotation == nil ? NSColor.secondaryLabelColor
                            : (receded ? NSColor.tertiaryLabelColor : NSColor.labelColor),
                    ]
                    let countSize = count.size(withAttributes: countAttributes)
                    let badge = countBadgeRect(size: countSize, row: hitRect, numberMinX: numberMinX)
                    if let badge {
                        let radius: CGFloat = annotation == nil ? badge.height / 2 : 3
                        (annotation == nil ? NSColor.quaternaryLabelColor : NSColor.clear).setFill()
                        NSBezierPath(roundedRect: badge, xRadius: radius, yRadius: radius).fill()
                        let stroke: NSColor = annotation == nil ? .separatorColor
                            : (receded ? .separatorColor : .controlAccentColor.withAlphaComponent(0.7))
                        stroke.setStroke()
                        let border = NSBezierPath(roundedRect: badge.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
                        border.lineWidth = 1
                        border.stroke()
                        count.draw(at: NSPoint(x: badge.midX - countSize.width / 2,
                                               y: badge.midY - countSize.height / 2), withAttributes: countAttributes)
                    }
                    let noun = hidden == 1 ? "line" : "lines"
                    var description = "Collapsed function — \(hidden) \(noun) hidden"
                    if let annotation { description += " · \(annotation.accessibilityDescription)" }
                    collapsedFunctionDescriptions.append(description)
                    let tag = addToolTip(hitRect.union(badge ?? hitRect), owner: self, userData: nil)
                    foldTooltips.append(tag)
                    foldTooltipText[tag] = description
                }
            }
        }
        if collapsedFunctionDescriptions.isEmpty {
            setAccessibilityHelp("Click a disclosure control to collapse or expand a source region.")
        } else {
            setAccessibilityHelp((["Click a disclosure control to collapse or expand a source region."]
                                  + collapsedFunctionDescriptions).joined(separator: " "))
        }
        window?.invalidateCursorRects(for: self)
    }

    /// The fold disclosure glyph, centered in the disclosure lane of `row`.
    private func drawDisclosure(_ symbol: String, in row: NSRect) {
        let markerFont = NSFont.systemFont(ofSize: Theme.foldMarkerSize, weight: .medium)
        let markerSize = (symbol as NSString).size(withAttributes: [.font: markerFont])
        (symbol as NSString).draw(at: NSPoint(x: (Theme.foldHitWidth - markerSize.width) / 2,
                                               y: row.minY + (row.height - markerSize.height) / 2),
                                  withAttributes: [.font: markerFont, .foregroundColor: NSColor.tertiaryLabelColor])
    }

    /// The neutral hidden-line capsule in the count lane beside `row`'s
    /// disclosure; returns its rectangle.
    private func drawCountCapsule(_ label: String, row: NSRect, numberMinX: CGFloat?) -> NSRect? {
        let count = label as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let size = count.size(withAttributes: attributes)
        guard let badge = countBadgeRect(size: size, row: row, numberMinX: numberMinX) else { return nil }
        let height = badge.height
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: badge, xRadius: height / 2, yRadius: height / 2).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: badge.insetBy(dx: 0.5, dy: 0.5), xRadius: height / 2, yRadius: height / 2)
        border.lineWidth = 1
        border.stroke()
        count.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
        return badge
    }

    /// Keep exact canonical numbers clear. A count that cannot fit stays in
    /// the existing tooltip/accessibility description rather than overlapping.
    private func countBadgeRect(size: NSSize, row: NSRect, numberMinX: CGFloat?) -> NSRect? {
        let x = Theme.foldHitWidth + 2
        let right = numberMinX.map { $0 - 3 } ?? (bounds.width - Theme.gutterInset)
        let width = max(14, min(32, size.width + 6))
        guard x + width <= right else { return nil }
        let height: CGFloat = 15
        return NSRect(x: x, y: row.midY - height / 2, width: width, height: height)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let id = testHitRects.first(where: { $0.value.contains(point) })?.key {
            onToggleTestRegion?(id)
            return
        }
        if let id = foldHitRects.first(where: { $0.value.contains(point) })?.key,
           let fold = folds.first(where: { $0.id == id }) {
            onToggleFold?(fold)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for rect in foldHitRects.values { addCursorRect(rect, cursor: .pointingHand) }
        for rect in testHitRects.values { addCursorRect(rect, cursor: .pointingHand) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag,
              point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        foldTooltipText[tag] ?? "Toggle source fold"
    }

    /// Binary search over sorted, disjoint one-based line ranges.
    static func isChanged(line: Int, in ranges: [Range<Int>]) -> Bool {
        var lower = 0
        var upper = ranges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let range = ranges[middle]
            if line < range.lowerBound { upper = middle } else if line >= range.upperBound { lower = middle + 1 } else { return true }
        }
        return false
    }

    private func fold(onHeaderLine line: Int, buffer: SourceBuffer) -> SourceFold? {
        folds.first { Self.headerLine(for: $0, in: buffer) == line }
    }

    static func headerLine(for fold: SourceFold, in buffer: SourceBuffer) -> Int {
        let start = buffer.line(atByte: fold.byteRange.lowerBound)
        return isDelimited(fold.byteRange, in: buffer) ? start : max(1, start - 1)
    }

    /// Counts canonical source rows removed by the fold. A visible delimiter
    /// remains on the header row; indentation bodies hide their captured rows.
    static func hiddenSourceLineCount(for fold: SourceFold, in buffer: SourceBuffer) -> Int {
        guard !fold.byteRange.isEmpty else { return 0 }
        let start = buffer.line(atByte: fold.byteRange.lowerBound)
        let lastByte = max(fold.byteRange.lowerBound, fold.byteRange.upperBound - 1)
        let end = buffer.line(atByte: lastByte)
        return isDelimited(fold.byteRange, in: buffer) ? max(0, end - start) : max(0, end - start + 1)
    }

    /// Logarithmic, capped scale fitting the compact disclosure lane.
    static func functionMeterWidth(hiddenLineCount: Int) -> CGFloat {
        let bounded = min(256, max(0, hiddenLineCount))
        return 6 + (Theme.foldHitWidth - 10) * log2(CGFloat(bounded) + 1) / log2(257)
    }

    /// Keep the badge compact for pathological generated functions while the
    /// tooltip and accessibility help retain the exact unabridged count.
    static func foldCountLabel(hiddenLineCount: Int) -> String {
        hiddenLineCount < 10_000 ? "\(max(0, hiddenLineCount))" : "9999+"
    }

    private static func isDelimited(_ range: Range<Int>, in buffer: SourceBuffer) -> Bool {
        let openers: Set<UInt8> = [0x7B, 0x5B, 0x28, 0x22, 0x27, 0x60]
        let closers: Set<UInt8> = [0x7D, 0x5D, 0x29, 0x22, 0x27, 0x60]
        guard range.lowerBound >= 0, range.upperBound <= buffer.data.count, range.count >= 2 else { return false }
        return openers.contains(buffer.data[range.lowerBound])
            && closers.contains(buffer.data[range.upperBound - 1])
    }

    static func shouldDrawLine(atUTF16 offset: Int, layout: NSLayoutManager, utf16Count: Int) -> Bool {
        guard offset >= 0, offset < utf16Count else { return true }
        let glyph = layout.glyphIndexForCharacter(at: offset)
        return !layout.notShownAttribute(forGlyphAt: glyph)
            && !layout.propertyForGlyph(at: glyph).contains(.null)
    }

    static func firstVisibleGlyph(in range: NSRange, layout: NSLayoutManager) -> Int? {
        guard range.length > 0 else { return nil }
        for glyph in range.location..<NSMaxRange(range) where glyph < layout.numberOfGlyphs {
            let property = layout.propertyForGlyph(at: glyph)
            if !property.contains(.null), !layout.notShownAttribute(forGlyphAt: glyph) { return glyph }
        }
        return nil
    }
}
