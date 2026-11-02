import AppKit
import SwiftUI

/// Read-only source surface. Besides the current-line and destination
/// highlights, it hosts the ⌘-hover affordance for semantic targets: an
/// underline and pointing hand only where an occurrence resolves to a
/// definition, ⌘-click to follow it, and context-menu actions.
final class ReaderTextView: NSTextView {
    struct PinnedDecoration: Equatable {
        let ranges: [NSRange]
        let colorSlot: Int
    }

    /// What the context menu needs to offer criticality marks for the SCIP
    /// symbol under the pointer. Nil for locals: their numbering is
    /// document-scoped and unstable across reindexing, so they are never
    /// marked persistently.
    struct CriticalityMenu: Equatable {
        let displayName: String
        let symbol: String
        let packageName: String?
        /// `scheme manager name`: the persisted key behind `packageName`.
        let packageKey: String?
        let builtIn: CriticalityClassification
        let symbolDecision: Criticality?
        let packageDecision: Criticality?
    }
    var destinationHighlightRange: NSRange?
    var destinationHighlightAlpha: CGFloat = 0
    /// Resolves a canonical byte offset to a target; nil when nothing is there.
    var semanticTarget: ((Int) -> SemanticTarget?)?
    var onSelectOccurrences: ((Int?) -> Void)?
    var onTogglePinnedOccurrences: ((Int?) -> Void)?
    var onGoToDefinition: ((Int) -> Void)?
    /// Return/Enter on a semantic symbol: (target byte, exact departure caret byte).
    var onKeyboardGoToDefinition: ((Int, Int) -> Void)?
    /// Plain x toggles the function owning this canonical caret byte.
    /// False means there is no foldable function and native handling continues.
    var onToggleEnclosingFunction: ((Int) -> Bool)?
    var onFindReferences: ((Int) -> Void)?
    var criticalityMenu: ((Int) -> CriticalityMenu?)?
    /// Critical-mode hover: the pointer rests on a byte (nil when it left the
    /// text). The model decides whether and when a popover appears.
    var onPointerOverSource: ((Int?) -> Void)?
    var pointerSummariesEnabled = false
    var onHoverNavigate: ((SemanticPosition?, String) -> Void)?
    var onPopoverHover: ((Bool) -> Void)?
    var onHoverDismiss: (() -> Void)?
    /// What the hover popover shows; nil closes it. Set by the viewer from
    /// the model, applied here to one NSPopover.
    var hoverPresentation: CriticalSummaryModel.HoverPresentation? {
        didSet { if hoverPresentation != oldValue { updateHoverPopover() } }
    }
    private var hoverPopover: NSPopover?
    private var hoverHost: HoverPopoverHost?
    private var hoverPopoverID: UUID?
    var onSetSymbolCriticality: ((String, Criticality?) -> Void)?
    var onSetPackageCriticality: ((String, Criticality?) -> Void)?
    private var menuCriticality: CriticalityMenu?
    /// UTF-16 offset → canonical byte, and back, through the owning buffer.
    var byteForUTF16: ((Int) -> Int)?
    var utf16RangeForBytes: ((Range<Int>) -> NSRange)?
    private(set) var hoverRange: NSRange?
    private var hoverByte: Int?
    private var trackingArea: NSTrackingArea?
    private var modifierMonitor: Any?
    private var menuByte: Int?
    var occurrenceHighlightRanges: [NSRange] = [] {
        didSet { if occurrenceHighlightRanges != oldValue { needsDisplay = true } }
    }
    var activeOccurrenceHighlightRange: NSRange? {
        didSet { if activeOccurrenceHighlightRange != oldValue { needsDisplay = true } }
    }
    /// UTF-16 range of the caret's function. A change repaints only the
    /// visible source; no layout is requested here, because this can be set
    /// while TextKit still holds the previous file.
    var functionShadeRange: NSRange? {
        didSet { if functionShadeRange != oldValue { setNeedsDisplay(visibleRect) } }
    }
    var pinnedOccurrenceDecorations: [PinnedDecoration] = [] {
        didSet { if pinnedOccurrenceDecorations != oldValue { needsDisplay = true } }
    }
    /// Whole-line UTF-16 ranges changed by a pull request, washed faintly
    /// (green for After additions, red for Before removals) beneath every
    /// other decoration. Drawing only; never an attribute or layout change.
    var changedCharacterRanges: [NSRange] = [] {
        didSet { if changedCharacterRanges != oldValue { setNeedsDisplay(visibleRect) } }
    }
    var changeRevision: ReviewRevision? {
        didSet { if changeRevision != oldValue { setNeedsDisplay(visibleRect) } }
    }
    /// Hide Tests: a quiet label after each test region's header text.
    /// Clicking it hides or shows that one region.
    struct TestRegionLabel: Equatable {
        let id: Int
        /// UTF-16 offset just past the header line's visible code.
        let headerEnd: Int
        let hiddenLineCount: Int
        let isHidden: Bool

        var title: String {
            guard isHidden else { return "Hide test code" }
            guard hiddenLineCount > 0 else { return "Test code" }
            return "Test code · \(hiddenLineCount) \(hiddenLineCount == 1 ? "line" : "lines") hidden"
        }
    }
    var testRegionLabels: [TestRegionLabel] = [] {
        didSet { if testRegionLabels != oldValue { setNeedsDisplay(visibleRect) } }
    }
    var onToggleTestRegion: ((Int) -> Void)?
    /// Where labels were last painted, for clicks and the pointing-hand cursor.
    private(set) var testLabelHitRects: [(id: Int, rect: NSRect)] = []

    /// Where the caret was last painted, so a focus change can repaint
    /// just that strip.
    private var paintedCaretRect: NSRect?
    private var windowKeyObservers: [NSObjectProtocol] = []

    isolated deinit {
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
        windowKeyObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let modifierMonitor { NSEvent.removeMonitor(modifierMonitor) }
        modifierMonitor = nil
        windowKeyObservers.forEach(NotificationCenter.default.removeObserver)
        windowKeyObservers = []
        guard let window else { return }
        // The caret shows only in the key window; repaint its strip when that changes.
        windowKeyObservers = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.invalidateInsertionCaret() }
            }
        }
        // `flagsChanged` is otherwise delivered only to the first responder.
        // A local monitor keeps Cmd-hover honest when the outline or search
        // field owns focus and the pointer is already resting over source.
        modifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.updateHoverForCurrentPointer(commandDown: event.modifierFlags.contains(.command))
            return event
        }
    }

    // MARK: - Function shade

    /// Full-width band over the source lines of `functionShadeRange` that
    /// intersect `visibleBounds`, from TextKit's line fragments. Only the
    /// visible slice of the function is mapped to glyphs, so a long function
    /// never forces glyph generation or layout beyond the viewport; folded bodies contribute no height because
    /// their null glyphs share the surviving line's fragment.
    func functionShadeRect(in visibleBounds: NSRect) -> NSRect? {
        guard let functionShadeRange else { return nil }
        return bandRect(for: functionShadeRange, in: visibleBounds)
    }

    /// Full-width band over the visible source lines of a UTF-16 range,
    /// from TextKit's line fragments; nil when nothing of it is visible.
    func bandRect(for characterRange: NSRange, in visibleBounds: NSRect) -> NSRect? {
        guard characterRange.length > 0, let layoutManager, let textContainer,
              NSMaxRange(characterRange) <= (string as NSString).length else { return nil }
        let local = visibleBounds.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: local, in: textContainer)
        // Intersect in character space first and map only the visible slice
        // back to glyphs: converting the whole function could generate glyphs
        // far past the viewport in a very long function.
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        guard let slice = visibleCharacters.intersection(characterRange), slice.length > 0 else { return nil }
        let shown = layoutManager.glyphRange(forCharacterRange: slice, actualCharacterRange: nil)
        guard shown.length > 0 else { return nil }
        let top = layoutManager.lineFragmentRect(forGlyphAt: shown.location, effectiveRange: nil)
        let bottom = layoutManager.lineFragmentRect(forGlyphAt: NSMaxRange(shown) - 1, effectiveRange: nil)
        return NSRect(x: 0, y: top.minY + textContainerOrigin.y,
                      width: max(bounds.width, visibleBounds.maxX), height: bottom.maxY - top.minY)
    }

    // MARK: - Insertion caret

    /// A read-only NSTextView draws no insertion point, and making it
    /// editable to get one is off the table. This paints a thin, steady
    /// caret at the empty selection's character boundary from TextKit's
    /// actual glyph geometry. It is the last thing `drawBackground` paints,
    /// so it sits above the current-line tint and every occurrence and pin
    /// decoration. (Overriding `draw(_:)` instead measurably changed
    /// NSTextView's scroll-position behavior, so it is deliberately avoided.)
    /// Selection changes already repaint the visible source for the
    /// current-line tint, so the caret needs no timers or stored positions.
    private func drawInsertionCaret(in dirtyRect: NSRect) {
        let caret = visibleInsertionCaretRect()
        paintedCaretRect = caret
        guard let caret, caret.intersects(dirtyRect) else { return }
        Theme.sourceCaretColor.setFill()
        caret.fill()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { invalidateInsertionCaret() }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { invalidateInsertionCaret() }
        return resigned
    }

    /// Whether the caret should show: this view is focused in the key window
    /// and the native selection is empty (a highlighted range is its own cue).
    var showsInsertionCaret: Bool {
        guard let window, window.isKeyWindow, window.firstResponder === self else { return false }
        return selectedRange().length == 0
    }

    func visibleInsertionCaretRect() -> NSRect? {
        guard showsInsertionCaret else { return nil }
        return insertionCaretRect(atCharacter: selectedRange().location)
    }

    /// The caret's rectangle (view coordinates) at a UTF-16 character
    /// boundary, from the laid-out glyphs: x is the glyph's typeset position
    /// (tabs, emoji, and proportional fallbacks included); y spans the font's
    /// ascender to descender around the line's real baseline. Nil inside
    /// folded (null-glyph) text or an empty document.
    func insertionCaretRect(atCharacter characterIndex: Int) -> NSRect? {
        guard let layoutManager, let textContainer, let textStorage, characterIndex != NSNotFound else { return nil }
        let length = textStorage.length
        guard length > 0 else { return nil }
        var index = min(max(0, characterIndex), length)
        // Snap into a composed character's start: the trailing UTF-16 units
        // of an emoji or ZWJ sequence carry null placeholder glyphs, which
        // must not read as folded text.
        if index < length { index = (textStorage.string as NSString).rangeOfComposedCharacterSequence(at: index).location }
        let x: CGFloat
        let baseline: CGFloat
        let fontIndex: Int
        if index < length {
            let glyph = layoutManager.glyphIndexForCharacter(at: index)
            guard glyph < layoutManager.numberOfGlyphs,
                  !layoutManager.propertyForGlyph(at: glyph).contains(.null) else { return nil }
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let location = layoutManager.location(forGlyphAt: glyph)
            x = fragment.minX + location.x
            baseline = fragment.minY + location.y
            fontIndex = index
        } else {
            // End of document: after the last composed character (its whole
            // glyph span, so a final emoji, ZWJ, or combining sequence is
            // measured entirely), or at the start of the empty line that
            // follows a final newline. Hidden-fold rejection uses the span's
            // first glyph, which only a fold marks null.
            let lastCharacter = (textStorage.string as NSString).rangeOfComposedCharacterSequence(at: length - 1)
            let span = layoutManager.glyphRange(forCharacterRange: lastCharacter, actualCharacterRange: nil)
            let last = span.location
            guard span.length > 0, last < layoutManager.numberOfGlyphs,
                  !layoutManager.propertyForGlyph(at: last).contains(.null) else { return nil }
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: last, effectiveRange: nil)
            let location = layoutManager.location(forGlyphAt: last)
            fontIndex = lastCharacter.location
            if (textStorage.string as NSString).character(at: length - 1) == 0x0A {
                let extra = layoutManager.extraLineFragmentRect
                let lineOrigin = extra.isEmpty ? NSPoint(x: fragment.minX, y: fragment.maxY) : extra.origin
                x = lineOrigin.x + textContainer.lineFragmentPadding
                baseline = lineOrigin.y + location.y
            } else {
                x = layoutManager.boundingRect(forGlyphRange: span, in: textContainer).maxX
                baseline = fragment.minY + location.y
            }
        }
        let font = textStorage.attribute(.font, at: fontIndex, effectiveRange: nil) as? NSFont
            ?? self.font ?? .monospacedSystemFont(ofSize: Theme.sourceFontSize, weight: .regular)
        let width = Theme.sourceCaretWidth
        let rect = NSRect(x: x + textContainerOrigin.x - width / 2, y: baseline + textContainerOrigin.y - font.ascender,
                          width: width, height: font.ascender - font.descender)
        return backingAlignedRect(rect, options: .alignAllEdgesNearest)
    }

    /// Repaints only the caret strips (old and new), never the document.
    func invalidateInsertionCaret() {
        if let paintedCaretRect { setNeedsDisplay(paintedCaretRect.insetBy(dx: -1, dy: -1)) }
        if let rect = selectedRange().length == 0 ? insertionCaretRect(atCharacter: selectedRange().location) : nil {
            setNeedsDisplay(rect.insetBy(dx: -1, dy: -1))
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard layoutManager != nil, textContainer != nil, !string.isEmpty else { return }
        // Bottom layer: the caret's function, beneath the line tint,
        // occurrence and pin decorations, and the caret.
        if let band = functionShadeRect(in: visibleRect)?.intersection(rect), !band.isEmpty {
            Theme.functionShadeColor(appearance: effectiveAppearance).setFill()
            band.fill()
        }
        if let changeRevision, !changedCharacterRanges.isEmpty {
            Theme.changeWashColor(revision: changeRevision, appearance: effectiveAppearance).setFill()
            for range in changedCharacterRanges {
                if let band = bandRect(for: range, in: visibleRect)?.intersection(rect), !band.isEmpty { band.fill() }
            }
        }
        if let destinationHighlightRange, destinationHighlightAlpha > 0 {
            drawLine(at: destinationHighlightRange.location, in: rect,
                     color: .controlAccentColor.withAlphaComponent(destinationHighlightAlpha))
        }
        let index = min(selectedRange().location, (string as NSString).length - 1)
        drawLine(at: max(0, index), in: rect, color: .controlAccentColor.withAlphaComponent(0.05))
        for decoration in pinnedOccurrenceDecorations {
            let colors = Theme.pinnedOccurrenceColors(slot: decoration.colorSlot, appearance: effectiveAppearance)
            for range in decoration.ranges {
                drawOccurrence(range, in: rect, color: colors.fill, strokeColor: colors.stroke, lineWidth: 1.4)
            }
        }
        for range in occurrenceHighlightRanges where range != activeOccurrenceHighlightRange {
            drawOccurrence(range, in: rect, color: Theme.semanticOccurrenceColor)
        }
        if let activeOccurrenceHighlightRange {
            drawOccurrence(activeOccurrenceHighlightRange, in: rect,
                           color: Theme.activeSemanticOccurrenceColor,
                           strokeColor: .controlAccentColor.withAlphaComponent(0.55))
        }
        drawTestRegionLabels(in: rect)
        drawInsertionCaret(in: rect)
    }

    // MARK: - Hidden test regions

    /// Label typography follows the source size, three points smaller and
    /// proportional, so it reads as an interface note rather than code.
    private var testLabelFont: NSFont {
        NSFont.systemFont(ofSize: max(10, (font?.pointSize ?? Theme.sourceFontSize) - 3), weight: .regular)
    }

    /// The label's rectangle after its header's last visible glyph, or nil
    /// when the header is outside `visibleBounds` (only visible headers are
    /// mapped, so a long document never generates layout for labels).
    func testLabelRect(for label: TestRegionLabel, in visibleBounds: NSRect) -> NSRect? {
        guard let layoutManager, let textContainer, label.headerEnd > 0,
              label.headerEnd <= (string as NSString).length else { return nil }
        let local = visibleBounds.offsetBy(dx: -textContainerOrigin.x, dy: -textContainerOrigin.y)
        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: local, in: textContainer)
        let visibleCharacters = layoutManager.characterRange(forGlyphRange: visibleGlyphs, actualGlyphRange: nil)
        let last = label.headerEnd - 1
        guard NSLocationInRange(last, visibleCharacters) else { return nil }
        // A character-range mapping can expand to the parent's surviving fold
        // glyph. Check the actual header character before using that geometry.
        let headerGlyph = layoutManager.glyphIndexForCharacter(at: last)
        guard NSLocationInRange(headerGlyph, visibleGlyphs),
              !layoutManager.propertyForGlyph(at: headerGlyph).contains(.null),
              !layoutManager.notShownAttribute(forGlyphAt: headerGlyph) else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: last, length: 1), actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        let glyphBounds = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let size = (label.title as NSString).size(withAttributes: [.font: testLabelFont])
        let height = ceil(size.height) + 2
        return NSRect(x: glyphBounds.maxX + textContainerOrigin.x + 12,
                      y: fragment.midY + textContainerOrigin.y - height / 2,
                      width: ceil(size.width) + 14, height: height)
    }

    private func drawTestRegionLabels(in dirtyRect: NSRect) {
        var hitRects: [(id: Int, rect: NSRect)] = []
        for label in testRegionLabels {
            guard let rect = testLabelRect(for: label, in: visibleRect) else { continue }
            hitRects.append((label.id, rect))
            guard rect.intersects(dirtyRect) else { continue }
            NSColor.quaternaryLabelColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: testLabelFont,
                .foregroundColor: label.isHidden ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor,
            ]
            let size = (label.title as NSString).size(withAttributes: attributes)
            (label.title as NSString).draw(at: NSPoint(x: rect.minX + 7, y: rect.midY - size.height / 2),
                                           withAttributes: attributes)
        }
        let geometryChanged = hitRects.map(\.rect) != testLabelHitRects.map(\.rect)
        // New documents can reuse the same geometry with different byte IDs.
        testLabelHitRects = hitRects
        if geometryChanged { window?.invalidateCursorRects(for: self) }
    }

    func testRegionLabel(at point: NSPoint) -> Int? {
        testLabelHitRects.first { $0.rect.contains(point) }?.id
    }

    /// Paints only glyphs TextKit currently shows. Null glyphs inside folds do
    /// not contribute rectangles, preventing hidden occurrences from stacking
    /// on the surviving fold line. This is drawing-only: no text attributes,
    /// selection, or canonical source storage are touched.
    private func drawOccurrence(_ characterRange: NSRange, in dirtyRect: NSRect,
                                color: NSColor, strokeColor: NSColor? = nil, lineWidth: CGFloat = 1) {
        guard let layoutManager, let textContainer,
              characterRange.length > 0,
              characterRange.location >= 0,
              NSMaxRange(characterRange) <= (string as NSString).length else { return }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: characterRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return }
        var shownStart: Int?
        let end = NSMaxRange(glyphRange)
        for glyph in glyphRange.location...end {
            let shown = glyph < end && !layoutManager.notShownAttribute(forGlyphAt: glyph)
            if shown, shownStart == nil { shownStart = glyph }
            if !shown, let start = shownStart {
                drawShownGlyphs(NSRange(location: start, length: glyph - start), in: dirtyRect,
                                container: textContainer, layout: layoutManager,
                                color: color, strokeColor: strokeColor, lineWidth: lineWidth)
                shownStart = nil
            }
        }
    }

    private func drawShownGlyphs(_ glyphRange: NSRange, in dirtyRect: NSRect,
                                 container: NSTextContainer, layout: NSLayoutManager,
                                 color: NSColor, strokeColor: NSColor?, lineWidth: CGFloat) {
        layout.enumerateEnclosingRects(forGlyphRange: glyphRange, withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { [self] rect, _ in
            var highlight = rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            highlight = highlight.insetBy(dx: -1.5, dy: 0)
            guard highlight.intersects(dirtyRect) else { return }
            let path = NSBezierPath(roundedRect: highlight, xRadius: 2.5, yRadius: 2.5)
            color.setFill()
            path.fill()
            if let strokeColor {
                strokeColor.setStroke()
                path.lineWidth = lineWidth
                path.stroke()
            }
        }
    }

    private func drawLine(at characterIndex: Int, in dirtyRect: NSRect, color: NSColor) {
        guard let layoutManager, let textContainer else { return }
        let clamped = min(max(0, characterIndex), max(0, (string as NSString).length - 1))
        let glyph = layoutManager.glyphIndexForCharacter(at: clamped)
        var line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        line.origin.y += textContainerOrigin.y
        line.origin.x = 0
        line.size.width = max(bounds.width, textContainer.size.width.isFinite ? min(textContainer.size.width, bounds.width) : bounds.width)
        color.setFill()
        line.intersection(dirtyRect).fill()
    }

    // MARK: - Semantic hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if retainHoverDuringTransit(event) { return }
        onPopoverHover?(false)
        updateHover(with: event)
        if pointerSummariesEnabled { onPointerOverSource?(byte(at: convert(event.locationInWindow, from: nil))) }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHover()
        if retainHoverDuringTransit(event) { return }
        onPopoverHover?(false)
        if pointerSummariesEnabled { onPointerOverSource?(nil) }
    }

    // MARK: - Hover popover

    /// The anchor rectangle of the hovered occurrence in view coordinates,
    /// or nil when it is folded away or no longer fits the text.
    func hoverAnchorRect(for byteRange: Range<Int>) -> NSRect? {
        guard let layoutManager, let textContainer, let utf16RangeForBytes else { return nil }
        let range = utf16RangeForBytes(byteRange)
        guard range.length > 0, NSMaxRange(range) <= (string as NSString).length else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        guard glyphs.length > 0, !layoutManager.notShownAttribute(forGlyphAt: glyphs.location) else { return nil }
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        return rect.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
    }

    private func updateHoverPopover() {
        guard let presentation = hoverPresentation, let anchor = hoverAnchorRect(for: presentation.byteRange) else {
            dismissHoverPopover()
            return
        }
        if let hoverPopover, let hoverHost, hoverPopoverID == presentation.id, hoverPopover.isShown {
            hoverHost.content.presentation = presentation
            return
        }
        dismissHoverPopover()
        let host = HoverPopoverHost(presentation: presentation,
                                    navigate: { [weak self] position, name in self?.onHoverNavigate?(position, name) },
                                    hovered: { [weak self] inside in self?.onPopoverHover?(inside) })
        let popover = NSPopover()
        popover.contentViewController = host
        popover.behavior = .semitransient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        hoverPopover = popover
        hoverHost = host
        hoverPopoverID = presentation.id
        popover.show(relativeTo: anchor, of: self, preferredEdge: .maxY)
    }

    private func dismissHoverPopover() {
        guard let hoverPopover else { return }
        hoverPopover.delegate = nil
        if hoverPopover.isShown { hoverPopover.close() }
        self.hoverPopover = nil
        hoverHost = nil
        hoverPopoverID = nil
    }

    /// Bridge the physical gap and source text between the anchor and popup.
    /// Crossing another token en route must not replace the popup being entered.
    private func retainHoverDuringTransit(_ event: NSEvent) -> Bool {
        guard let popoverWindow = hoverHost?.view.window, isHoverPopoverShown,
              let presentation = hoverPresentation, let anchor = hoverAnchorRect(for: presentation.byteRange),
              let window, let eventWindow = event.window else { return false }
        let screenAnchor = window.convertToScreen(convert(anchor, to: nil))
        let point = eventWindow.convertPoint(toScreen: event.locationInWindow)
        guard Self.hoverTransitContains(point, anchor: screenAnchor, popover: popoverWindow.frame) else { return false }
        onPopoverHover?(true)
        return true
    }

    static func hoverTransitContains(_ point: NSPoint, anchor: NSRect, popover: NSRect) -> Bool {
        anchor.union(popover).insetBy(dx: -6, dy: -6).contains(point)
    }

    /// Whether a hover popover is on screen (tests and the coordinator).
    var isHoverPopoverShown: Bool { hoverPopover?.isShown == true }

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        updateHoverForCurrentPointer(commandDown: event.modifierFlags.contains(.command))
    }

    private func updateHoverForCurrentPointer(commandDown: Bool) {
        guard commandDown, let window else { clearHover(); return }
        let location = window.mouseLocationOutsideOfEventStream
        updateHover(at: convert(location, from: nil), commandDown: true)
    }

    private func updateHover(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil), commandDown: event.modifierFlags.contains(.command))
    }

    private func updateHover(at point: NSPoint, commandDown: Bool) {
        guard commandDown, let byte = byte(at: point), let target = semanticTarget?(byte), target.hasDefinition,
              let range = utf16RangeForBytes?(target.byteRange), range.length > 0 else {
            clearHover()
            return
        }
        guard range != hoverRange else { return }
        clearHover()
        hoverRange = range
        hoverByte = byte
        layoutManager?.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.single.rawValue,
                                               .underlineColor: Theme.semanticUnderlineColor], forCharacterRange: range)
        NSCursor.pointingHand.set()
    }

    /// Removes the affordance. Safe to call at any time, including after the
    /// index or buffer behind it was replaced.
    func clearHover() {
        if let hoverRange, let layoutManager, NSMaxRange(hoverRange) <= (string as NSString).length {
            layoutManager.removeTemporaryAttribute(.underlineStyle, forCharacterRange: hoverRange)
            layoutManager.removeTemporaryAttribute(.underlineColor, forCharacterRange: hoverRange)
        }
        if hoverRange != nil { NSCursor.iBeam.set() }
        hoverRange = nil
        hoverByte = nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for entry in testLabelHitRects { addCursorRect(entry.rect, cursor: .pointingHand) }
        if hoverRange != nil { NSCursor.pointingHand.set() }
    }

    /// The canonical byte under a view point, or nil when the point is past the
    /// end of a line, inside folded (not shown) text, or outside the text.
    func byte(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, !string.isEmpty else { return nil }
        let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyph = layoutManager.glyphIndex(for: local, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard glyph < layoutManager.numberOfGlyphs, !layoutManager.notShownAttribute(forGlyphAt: glyph) else { return nil }
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard rect.insetBy(dx: -1, dy: -1).contains(local) else { return nil }
        let character = layoutManager.characterIndexForGlyph(at: glyph)
        return byteForUTF16?(character)
    }

    // MARK: - Return / Enter

    static let returnKeyCode: UInt16 = 36
    static let keypadEnterKeyCode: UInt16 = 76

    /// Plain x toggles the named function at the selection's caret byte.
    /// Plain Return or keypad Enter follows the semantic symbol under the
    /// caret or the native selection to its in-repository definition, like
    /// ⌘-click. Anything else — modified keys, no SCIP target, a target with
    /// no in-repository definition (external, or the caret already on the
    /// definition), or a selection that is not inside one occurrence — falls
    /// through to the text view unchanged. Commands stay local to this reader.
    override func keyDown(with event: NSEvent) {
        if hoverPresentation != nil { onHoverDismiss?() }
        if let byte = keyboardFunctionFoldByte(for: event), let toggle = onToggleEnclosingFunction {
            // Holding the key must not repeatedly flip the same fold.
            if event.isARepeat { return }
            if toggle(byte) {
                clearHover()
                return
            }
        }
        if let route = keyboardDefinitionRoute(for: event) {
            clearHover()
            onKeyboardGoToDefinition?(route.target, route.departure)
            return
        }
        super.keyDown(with: event)
    }

    func keyboardFunctionFoldByte(for event: NSEvent) -> Int? {
        guard !isEditable, event.type == .keyDown, event.characters?.lowercased() == "x",
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              !hasMarkedText(), let byteForUTF16 else { return nil }
        let selection = selectedRange()
        guard selection.location != NSNotFound else { return nil }
        return byteForUTF16(selection.location)
    }

    /// The (target, departure) bytes a Return/Enter event would follow, or nil.
    func keyboardDefinitionRoute(for event: NSEvent) -> (target: Int, departure: Int)? {
        guard event.type == .keyDown,
              event.keyCode == Self.returnKeyCode || event.keyCode == Self.keypadEnterKeyCode,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              !hasMarkedText(), let byteForUTF16, let semanticTarget else { return nil }
        let selection = selectedRange()
        guard selection.location != NSNotFound else { return nil }
        let start = byteForUTF16(selection.location)
        if selection.length > 0 {
            // A highlighted word must lie within one occurrence.
            let end = byteForUTF16(NSMaxRange(selection))
            guard let target = semanticTarget(start), target.hasDefinition,
                  target.byteRange.lowerBound <= start, end <= target.byteRange.upperBound else { return nil }
            return (start, start)
        }
        if let target = semanticTarget(start), target.hasDefinition { return (start, start) }
        // A caret just past an identifier (after arrowing to its end) still
        // means that occurrence; the departure stays the caret itself.
        if start > 0, let target = semanticTarget(start - 1), target.hasDefinition,
           target.byteRange.upperBound == start {
            return (start - 1, start)
        }
        return nil
    }

    // MARK: - Clicks and menus

    override func mouseDown(with event: NSEvent) {
        if hoverPresentation != nil { onHoverDismiss?() }
        if event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
           let id = testRegionLabel(at: convert(event.locationInWindow, from: nil)) {
            onToggleTestRegion?(id)
            return
        }
        if event.modifierFlags.contains(.command) {
            if event.clickCount == 1,
               let byte = byte(at: convert(event.locationInWindow, from: nil)),
               let target = semanticTarget?(byte), target.hasDefinition {
                clearHover()
                onGoToDefinition?(byte)
            } else {
                super.mouseDown(with: event)
            }
            return
        }
        let selectedByte = event.clickCount <= 2 ? byte(at: convert(event.locationInWindow, from: nil)) : nil
        super.mouseDown(with: event)
        if event.clickCount >= 2 {
            onTogglePinnedOccurrences?(selectedByte)
        } else if event.clickCount == 1 && selectedRange().length == 0 {
            onSelectOccurrences?(selectedByte)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        guard let byte = byte(at: convert(event.locationInWindow, from: nil)), let target = semanticTarget?(byte) else { return menu }
        menuByte = byte
        let definition = NSMenuItem(title: "Go to Definition of \u{201C}\(target.displayName)\u{201D}", action: #selector(goToDefinitionFromMenu), keyEquivalent: "")
        definition.target = self
        definition.isEnabled = target.hasDefinition
        let references = NSMenuItem(title: "Find References to \u{201C}\(target.displayName)\u{201D}", action: #selector(findReferencesFromMenu), keyEquivalent: "")
        references.target = self
        var insertAt = 0
        menu.insertItem(definition, at: insertAt); insertAt += 1
        menu.insertItem(references, at: insertAt); insertAt += 1
        if let marks = criticalityMenu?(byte) {
            menuCriticality = marks
            menu.insertItem(NSMenuItem.separator(), at: insertAt); insertAt += 1
            menu.insertItem(markSubmenu(title: "Mark \u{201C}\(marks.displayName)\u{201D}", decision: marks.symbolDecision,
                                        builtInTitle: "Built-In (\(marks.builtIn.criticality.title) \u{00B7} \(marks.builtIn.reason.description))",
                                        action: #selector(setSymbolCriticality(_:))), at: insertAt)
            insertAt += 1
            if let package = marks.packageName {
                menu.insertItem(markSubmenu(title: "Mark Package \u{201C}\(package)\u{201D}", decision: marks.packageDecision,
                                            builtInTitle: "Built-In", action: #selector(setPackageCriticality(_:))), at: insertAt)
                insertAt += 1
            }
        } else {
            menuCriticality = nil
        }
        menu.insertItem(NSMenuItem.separator(), at: insertAt)
        menu.autoenablesItems = false
        return menu
    }

    /// A radio group: Critical, Non-Critical, then Built-In (which names the
    /// built-in result for a symbol). The checked item is the active choice;
    /// choosing Built-In removes the stored decision.
    private func markSubmenu(title: String, decision: Criticality?, builtInTitle: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: title)
        submenu.autoenablesItems = false
        let choices: [(String, Criticality?)] = [("Critical", .critical), ("Non-Critical", .ordinary)]
        for (label, value) in choices {
            let choice = NSMenuItem(title: label, action: action, keyEquivalent: "")
            choice.target = self
            choice.representedObject = value?.rawValue
            choice.state = decision == value ? .on : .off
            submenu.addItem(choice)
        }
        submenu.addItem(.separator())
        let builtIn = NSMenuItem(title: builtInTitle, action: action, keyEquivalent: "")
        builtIn.target = self
        builtIn.representedObject = nil
        builtIn.state = decision == nil ? .on : .off
        submenu.addItem(builtIn)
        item.submenu = submenu
        return item
    }

    @objc private func setSymbolCriticality(_ sender: NSMenuItem) {
        guard let menuCriticality else { return }
        onSetSymbolCriticality?(menuCriticality.symbol, (sender.representedObject as? String).flatMap(Criticality.init(rawValue:)))
    }

    @objc private func setPackageCriticality(_ sender: NSMenuItem) {
        guard let menuCriticality, let package = menuCriticality.packageKey else { return }
        onSetPackageCriticality?(package, (sender.representedObject as? String).flatMap(Criticality.init(rawValue:)))
    }

    @objc private func goToDefinitionFromMenu() {
        if let menuByte { onGoToDefinition?(menuByte) }
    }

    @objc private func findReferencesFromMenu() {
        if let menuByte { onFindReferences?(menuByte) }
    }
}

extension ReaderTextView: NSPopoverDelegate {
    /// The system closed it (a click elsewhere): tell the model so its state
    /// matches the screen.
    func popoverDidClose(_ notification: Notification) {
        onHoverDismiss?()
    }
}
