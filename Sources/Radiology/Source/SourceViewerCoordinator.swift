import AppKit

@MainActor
final class SourceViewerCoordinator: NSObject, NSTextViewDelegate {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    weak var gutter: LineNumberGutter?
    var buffer: SourceBuffer?
    var syntax: SyntaxSnapshot?
    var onPosition: ((Int, Int) -> Void)?
    var onCaret: ((Int) -> Void)?
    var revision = -1
    var focusRevision = -1
    private var foldToDefinitionsRevision: Int?
    private var collapseFunctionsRevision: Int?
    var reviewIdentity: String?
    private var appliedReviewDefaults = false
    private var manualFoldIDs = Set<String>()
    private var manualDefaultOverride = false
    var highlightRevision = 0
    var semanticRevision = -1
    var updating = false
    var programmaticPositionByte: Int?
    private var foldedIDs = Set<String>()
    private var foldedCharacterRanges: [NSRange] = []
    /// Sorted, disjoint UTF-16 ranges the active projection recedes. Used
    /// only at draw time through `shouldUseTemporaryAttributes`; nothing in
    /// the text storage or layout changes.
    private(set) var recededCharacterRanges: [NSRange] = []
    /// The projection's own receded ranges, before hidden-test headers join.
    private var projectionCharacterRanges: [NSRange] = []
    private var appliedProjectionID: UUID?
    /// Hide Tests for the buffer in TextKit: hidden ranges join the fold
    /// union; headers recede with the projection. See plans/source-filters.md.
    private(set) var testPresentation: TestCodePresentation?
    private var testHeaderCharacterRanges: [NSRange] = []
    /// How often TextKit consulted the projection hook; tests use it to prove
    /// the draw path really asks (it does so for every drawn run, with or
    /// without temporary attributes present).
    private(set) var projectionHookCalls = 0
    private var highlightTask: Task<Void, Never>?
    private var navigationLayoutTask: Task<Void, Never>?
    private var appliedDefaultFunctionFolds = false

    // MARK: - Projection

    /// Installs (or clears) the projection's receded ranges for the buffer
    /// currently in TextKit and repaints the visible source. Equal
    /// projections are not reapplied, so caret-driven updates cost one
    /// identity comparison.
    func applyProjection(_ projection: SourceProjection?, buffer: SourceBuffer) {
        guard projection?.id != appliedProjectionID else { return }
        appliedProjectionID = projection?.id
        projectionCharacterRanges = (projection?.recededByteRanges ?? []).map(buffer.utf16Range(forByteRange:))
            .filter { $0.length > 0 }
        recededCharacterRanges = Self.union(projectionCharacterRanges + testHeaderCharacterRanges)
        guard let textView, let layout = textView.layoutManager else { return }
        if layout.delegate !== self { layout.delegate = self }
        textView.setNeedsDisplay(textView.visibleRect)
    }

    /// Records Hide Tests' presentation (already matched to the buffer the
    /// viewer is showing). Returns whether it changed; ranges are converted
    /// by the next `applyFoldAttributes`, after any source replacement.
    func setTestPresentation(_ presentation: TestCodePresentation?) -> Bool {
        guard presentation != testPresentation else { return false }
        testPresentation = presentation
        return true
    }

    /// Sorted, disjoint union of UTF-16 ranges; overlapping or touching
    /// ranges merge, contained ranges vanish.
    static func union(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.filter { $0.length > 0 }.sorted {
            $0.location == $1.location ? $0.length > $1.length : $0.location < $1.location
        }
        var merged: [NSRange] = []
        for candidate in sorted {
            if let last = merged.last, candidate.location <= NSMaxRange(last) {
                if NSMaxRange(candidate) > NSMaxRange(last) {
                    merged[merged.count - 1] = NSRange(location: last.location, length: NSMaxRange(candidate) - last.location)
                }
            } else {
                merged.append(candidate)
            }
        }
        return merged
    }

    /// The presentation when it belongs to `buffer`; nil for other bytes.
    private func testPresentation(for buffer: SourceBuffer) -> TestCodePresentation? {
        guard let testPresentation, testPresentation.path == buffer.path,
              testPresentation.sourceIdentity.byteCount == buffer.data.count else { return nil }
        return testPresentation
    }

    /// Pushes Hide Tests' header dimming, gutter markers, and inline labels
    /// for the buffer in TextKit; returns the hidden UTF-16 ranges.
    private func applyTestPresentation(buffer: SourceBuffer, textView: NSTextView) -> [NSRange] {
        let presentation = testPresentation(for: buffer)
        let hidden = presentation?.hiddenRegions ?? []
        let headers = hidden.map { buffer.utf16Range(forByteRange: $0.headerByteRange) }
        if headers != testHeaderCharacterRanges {
            testHeaderCharacterRanges = headers
            recededCharacterRanges = Self.union(projectionCharacterRanges + testHeaderCharacterRanges)
            if textView.layoutManager?.delegate !== self { textView.layoutManager?.delegate = self }
            textView.setNeedsDisplay(textView.visibleRect)
        }
        gutter?.testMarkers = hidden.map {
            LineNumberGutter.TestMarker(id: $0.id, headerLine: $0.headerLine, hiddenLineCount: $0.hiddenLineCount)
        }
        (textView as? ReaderTextView)?.testRegionLabels = (presentation?.regions ?? []).map { region in
            ReaderTextView.TestRegionLabel(id: region.id,
                                           headerEnd: buffer.utf16Offset(forByte: region.headerByteRange.upperBound),
                                           hiddenLineCount: region.hiddenLineCount, isHidden: region.isHidden)
        }
        return hidden.map { buffer.utf16Range(forByteRange: $0.hiddenByteRange) }
    }

    /// The receded range containing `location`, or the gap up to the next
    /// receded range. Binary search over the sorted disjoint array.
    func recededRun(at location: Int) -> (isReceded: Bool, range: NSRange) {
        var lower = 0
        var upper = recededCharacterRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let range = recededCharacterRanges[middle]
            if location < range.location {
                upper = middle
            } else if location >= NSMaxRange(range) {
                lower = middle + 1
            } else {
                return (true, range)
            }
        }
        let next = lower < recededCharacterRanges.count ? recededCharacterRanges[lower].location : Int.max
        return (false, NSRange(location: location, length: max(0, next - location)))
    }

    /// `foldedCharacterRanges` is sorted and disjoint. Glyph generation is a
    /// per-character hot path, so membership must be logarithmic rather than a
    /// linear scan across every function in a large file.
    private func isCharacterFolded(_ location: Int) -> Bool {
        var lower = 0
        var upper = foldedCharacterRanges.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            let range = foldedCharacterRanges[middle]
            if location < range.location {
                upper = middle
            } else if location >= NSMaxRange(range) {
                lower = middle + 1
            } else {
                return true
            }
        }
        return false
    }

    /// Returns true when function folds were applied for the first time for
    /// this loaded buffer. The caller can then re-reveal a pending target.
    func updateSyntax(_ snapshot: SyntaxSnapshot?, buffer: SourceBuffer, resetFolds: Bool) -> Bool {
        self.buffer = buffer
        syntax = snapshot
        if resetFolds {
            foldedIDs.removeAll()
            appliedDefaultFunctionFolds = false
            appliedReviewDefaults = false
            manualFoldIDs.removeAll()
            manualDefaultOverride = false
        }
        var appliedDefault = false
        if let snapshot, !appliedDefaultFunctionFolds {
            appliedDefaultFunctionFolds = true
            // `updateSyntax` runs before SourceViewer replaces TextKit's
            // attributed string. Only update fold state here: invalidating
            // glyphs with ranges from the new buffer while the layout manager
            // still owns the previous file can raise NSRunStorage exceptions.
            foldedIDs.formUnion(snapshot.folds.lazy.filter { $0.kind == "function" }.map(\.id))
            appliedDefault = true
        }
        gutter?.foldedIDs = foldedIDs
        return appliedDefault
    }

    /// Adopt old command counters on a new coordinator; only subsequent commands
    /// override this document. State changes precede the single combined layout.
    func consumeFoldCommands(definitions: Int, functions: Int) -> Bool {
        let doDefinitions = foldToDefinitionsRevision.map { $0 != definitions } ?? false
        let doFunctions = collapseFunctionsRevision.map { $0 != functions } ?? false
        foldToDefinitionsRevision = definitions
        collapseFunctionsRevision = functions
        if doDefinitions { foldToDefinitions(applyAttributes: false) }
        if doFunctions { collapseFunctions(applyAttributes: false) }
        return doDefinitions || doFunctions
    }

    var reviewDefaultsPending: Bool { !appliedReviewDefaults }

    func applyInitialReviewFolds(_ input: ReviewFoldInput?, sourceIdentity: SourceContentIdentity?) -> Bool {
        guard !appliedReviewDefaults, let input, let buffer, let syntax, appliedDefaultFunctionFolds,
              input.reviewID == reviewIdentity, input.path == buffer.path, syntax.path == buffer.path,
              input.revision == buffer.revision, input.sourceIdentity == sourceIdentity else { return false }
        appliedReviewDefaults = true
        guard !manualDefaultOverride else { return false }
        let before = foldedIDs
        foldedIDs.subtract(input.foldsToExpand(in: syntax, buffer: buffer).subtracting(manualFoldIDs))
        gutter?.foldedIDs = foldedIDs
        return foldedIDs != before
    }

    /// Preserve the source row at the top of the viewport when late hunks open
    /// folds. Never replay the file's old navigation target or alter selection.
    func visibleTopCharacter() -> Int? {
        guard let textView, let scrollView, let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
        let rect = scrollView.contentView.bounds.offsetBy(dx: -textView.textContainerOrigin.x, dy: -textView.textContainerOrigin.y)
        let glyphs = layout.glyphRange(forBoundingRect: NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: 1), in: container)
        guard let glyph = LineNumberGutter.firstVisibleGlyph(in: glyphs, layout: layout) else { return nil }
        return layout.characterIndexForGlyph(at: glyph)
    }

    func preserveViewport(atCharacter character: Int) {
        navigationLayoutTask?.cancel()
        programmaticPositionByte = nil
        guard let scroll = scrollView as? SourceScrollView else { return }
        scroll.pendingLocation = nil
        scroll.pendingViewportCharacter = character
        scroll.needsLayout = true
    }

    func toggleFold(_ fold: SourceFold) {
        setFold(fold, folded: !foldedIDs.contains(fold.id))
    }

    /// A source-local keyboard action: toggle the innermost named callable.
    /// If an enclosing fold hides it, expansion also opens those ancestors so
    /// the action has a visible effect. Sibling/nested fold choices survive.
    @discardableResult
    func toggleFunction(at byte: Int) -> Bool {
        guard let buffer, let syntax, syntax.path == buffer.path,
              let target = syntax.enclosingFunctionFold(at: byte) else { return false }
        let ancestors = syntax.folds.filter {
            $0.id != target.fold.id && foldedIDs.contains($0.id)
                && $0.byteRange.lowerBound <= target.function.byteRange.lowerBound
                && target.function.byteRange.upperBound <= $0.byteRange.upperBound
        }.map(\.id)
        let collapse = !foldedIDs.contains(target.fold.id) && ancestors.isEmpty
        foldedIDs.subtract(ancestors)
        manualFoldIDs.formUnion(ancestors)
        setFold(target.fold, folded: collapse)
        return true
    }

    private func setFold(_ fold: SourceFold, folded: Bool) {
        manualFoldIDs.insert(fold.id)
        if folded { foldedIDs.insert(fold.id) } else { foldedIDs.remove(fold.id) }
        applyFoldAttributes()
        gutter?.foldedIDs = foldedIDs
        gutter?.needsDisplay = true
    }

    func isFolded(_ fold: SourceFold) -> Bool { foldedIDs.contains(fold.id) }

    func foldToDefinitions(applyAttributes: Bool = true) {
        guard let syntax else { return }
        manualDefaultOverride = true
        foldedIDs = Set(syntax.folds.filter { fold in
            if fold.kind == "function" { return true }
            guard fold.kind == "type" else { return false }
            // Keep containers open when they expose nested declarations.
            return !syntax.symbols.contains {
                fold.byteRange.lowerBound <= $0.byteRange.lowerBound
                    && $0.byteRange.upperBound <= fold.byteRange.upperBound
            }
        }.map(\.id))
        if applyAttributes { applyFoldAttributes() }
        gutter?.foldedIDs = foldedIDs
        gutter?.needsDisplay = true
    }

    func collapseFunctions(applyAttributes: Bool = true) {
        guard let syntax else { return }
        manualDefaultOverride = true
        foldedIDs.formUnion(syntax.folds.lazy.filter { $0.kind == "function" }.map(\.id))
        if applyAttributes { applyFoldAttributes() }
        gutter?.foldedIDs = foldedIDs
        gutter?.needsDisplay = true
    }

    /// Explicit navigation opens the destination callable as well as its
    /// ancestors. Passive caret/viewport restoration only opens hiding folds.
    func reveal(byteOffset: Int, expandFunction: Bool = false, applyAttributes: Bool = true) {
        guard let syntax else { return }
        let functionID = expandFunction ? syntax.enclosingFunctionFold(at: byteOffset)?.fold.id : nil
        let hidden = syntax.folds.filter {
            foldedIDs.contains($0.id) && ($0.byteRange.contains(byteOffset) || $0.id == functionID)
        }
        guard !hidden.isEmpty else { return }
        foldedIDs.subtract(hidden.map(\.id))
        if applyAttributes { applyFoldAttributes() }
        gutter?.foldedIDs = foldedIDs
    }

    func flashDestination(atUTF16 offset: Int, hold: Duration = .milliseconds(900)) {
        guard let textView = textView as? ReaderTextView else { return }
        highlightTask?.cancel()
        textView.destinationHighlightRange = NSRange(location: offset, length: 0)
        textView.destinationHighlightAlpha = Theme.destinationHighlightAlpha
        textView.needsDisplay = true
        highlightTask = Task { @MainActor [weak self, weak textView] in
            try? await Task.sleep(for: hold)
            guard let self, let textView, !Task.isCancelled else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                clearDestinationHighlight(in: textView)
                return
            }
            for step in 1...6 {
                try? await Task.sleep(for: .milliseconds(35))
                guard !Task.isCancelled else { return }
                textView.destinationHighlightAlpha = Theme.destinationHighlightAlpha * CGFloat(6 - step) / 6
                textView.needsDisplay = true
            }
            clearDestinationHighlight(in: textView)
        }
    }

    func cancelDestinationHighlight() {
        highlightTask?.cancel()
        if let textView = textView as? ReaderTextView { clearDestinationHighlight(in: textView) }
    }

    func settleNavigation(atUTF16 offset: Int, revision: Int) {
        navigationLayoutTask?.cancel()
        navigationLayoutTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !Task.isCancelled, self.revision == revision,
                  let scrollView = self.scrollView as? SourceScrollView else { return }
            scrollView.pendingLocation = offset
            scrollView.needsLayout = true
            scrollView.layoutSubtreeIfNeeded()
        }
    }

    private func clearDestinationHighlight(in textView: ReaderTextView) {
        textView.destinationHighlightRange = nil
        textView.destinationHighlightAlpha = 0
        textView.needsDisplay = true
    }

    func applyFoldAttributes() {
        guard let textView, let buffer, let layout = textView.layoutManager else { return }
        (textView as? ReaderTextView)?.clearHover()
        let previousRanges = foldedCharacterRanges
        let activeFolds = (syntax?.folds ?? []).filter { foldedIDs.contains($0.id) }
        let hiddenTests = applyTestPresentation(buffer: buffer, textView: textView)
        // TextKit must see a disjoint set. Feeding both a collapsed function
        // and its nested local functions/closures into glyph generation can
        // replace the same glyph run twice, corrupting character mapping and
        // surfacing nested markers on the parent's surviving closing brace.
        // Hidden test code joins the same union: a fold inside or across a
        // test region never produces overlapping hidden runs.
        foldedCharacterRanges = Self.union(activeFolds.map { hiddenRange(for: $0, buffer: buffer) } + hiddenTests)
        guard previousRanges != foldedCharacterRanges else {
            gutter?.needsDisplay = true
            textView.needsDisplay = true
            return
        }
        if layout.delegate !== self { layout.delegate = self }
        let removed = previousRanges.filter { !foldedCharacterRanges.contains($0) }
        let added = foldedCharacterRanges.filter { !previousRanges.contains($0) }
        let changed = removed + added
        let invalidStart = changed.map(\.location).min() ?? 0
        let invalidEnd = changed.map(NSMaxRange).max() ?? buffer.utf16Count
        let glyphRange = NSRange(location: invalidStart, length: max(0, invalidEnd - invalidStart))
        let downstreamLayout = NSRange(location: invalidStart,
                                       length: max(0, buffer.utf16Count - invalidStart))
        layout.invalidateGlyphs(forCharacterRange: glyphRange,
                                changeInLength: 0, actualCharacterRange: nil)
        // Only the changed fold needs new glyph properties. Its height affects
        // every subsequent fragment, so downstream layout is invalidated while
        // the rest of the document's glyph cache remains intact.
        layout.invalidateLayout(forCharacterRange: downstreamLayout, actualCharacterRange: nil)
        textView.needsLayout = true
        textView.needsDisplay = true
    }

    /// Clears old-file fold state before TextKit's backing string is replaced.
    /// The delegate is detached only across the replacement boundary; toggling
    /// it during ordinary folds can make the typesetter briefly lay out every
    /// hidden newline and leave hundreds of empty fragments behind.
    func prepareForSourceReplacement() {
        foldedCharacterRanges.removeAll(keepingCapacity: true)
        recededCharacterRanges.removeAll(keepingCapacity: true)
        projectionCharacterRanges.removeAll(keepingCapacity: true)
        testHeaderCharacterRanges.removeAll(keepingCapacity: true)
        appliedProjectionID = nil
        textView?.layoutManager?.delegate = nil
    }

    func finishSourceReplacement() {
        textView?.layoutManager?.delegate = self
    }

    /// Brace-, bracket-, or quote-delimited bodies keep their delimiters
    /// visible, so a collapsed function still reads as `{}`. Bodies delimited
    /// by indentation instead — Python blocks, Kotlin `statements`, Swift
    /// `statements` — are hidden whole, because leaving their first and last
    /// characters behind would show meaningless fragments.
    private func hiddenRange(for fold: SourceFold, buffer: SourceBuffer) -> NSRange {
        let range = buffer.utf16Range(forByteRange: fold.byteRange)
        guard range.length > 0 else { return NSRange(location: range.location, length: 0) }
        guard isDelimited(fold.byteRange, in: buffer) else { return range }
        guard range.length > 2 else { return NSRange(location: range.location, length: 0) }
        return NSRange(location: range.location + 1, length: range.length - 2)
    }

    private func isDelimited(_ byteRange: Range<Int>, in buffer: SourceBuffer) -> Bool {
        let openers: Set<UInt8> = [0x7B, 0x5B, 0x28, 0x22, 0x27, 0x60]  // { [ ( " \' `
        let closers: Set<UInt8> = [0x7D, 0x5D, 0x29, 0x22, 0x27, 0x60]  // } ] ) " \' `
        guard byteRange.lowerBound >= 0, byteRange.upperBound <= buffer.data.count,
              byteRange.count >= 2 else { return false }
        return openers.contains(buffer.data[byteRange.lowerBound])
            && closers.contains(buffer.data[byteRange.upperBound - 1])
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !updating, let textView, let buffer else { return }
        let byte = buffer.byteOffset(forUTF16: textView.selectedRange().location)
        let line = buffer.line(atByte: byte)
        gutter?.needsDisplay = true
        textView.needsDisplay = true
        onPosition?(byte, line)
        onCaret?(byte)
    }

    @objc func didScroll(_ notification: Notification) {
        gutter?.needsDisplay = true
        if let reader = textView as? ReaderTextView, reader.hoverPresentation != nil { reader.onHoverDismiss?() }
        guard !updating, (scrollView as? SourceScrollView)?.isRestoringViewport != true,
              let textView, let buffer, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        if let byte = programmaticPositionByte {
            programmaticPositionByte = nil
            onPosition?(byte, buffer.line(atByte: byte))
            return
        }
        let point = NSPoint(x: 0, y: max(0, textView.visibleRect.minY))
        let glyph = layout.glyphIndex(for: point, in: container)
        let utf16 = glyph < layout.numberOfGlyphs ? layout.characterIndexForGlyph(at: glyph) : buffer.utf16Count
        let byte = buffer.byteOffset(forUTF16: utf16)
        let selectedByte = buffer.byteOffset(forUTF16: textView.selectedRange().location)
        onPosition?(byte, buffer.line(atByte: selectedByte))
    }
}

extension SourceViewerCoordinator: @preconcurrency NSLayoutManagerDelegate {
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>,
                       characterIndexes: UnsafePointer<Int>, font: NSFont,
                       forGlyphRange glyphRange: NSRange) -> Int {
        var adjusted = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        for index in adjusted.indices {
            if isCharacterFolded(characterIndexes[index]) {
                // Preserve TextKit's original glyph semantics and add only the
                // visibility bit. Hidden control characters receive a zero-
                // advancement action below, so newlines compact without
                // corrupting the glyph/character mapping after a large fold.
                adjusted[index].insert(.null)
            } else {
                adjusted[index].remove(.null)
            }
        }
        adjusted.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return }
            layoutManager.setGlyphs(glyphs, properties: baseAddress, characterIndexes: characterIndexes,
                                    font: font, forGlyphRange: glyphRange)
        }
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        isCharacterFolded(charIndex) ? .zeroAdvancement : action
    }

    /// Draw-time projection: inside a receded range the glyphs take the text
    /// storage's own foreground color (the current syntax role, whichever
    /// highlights have arrived) at reduced opacity. Incoming temporary
    /// attributes such as the ⌘-hover underline are kept. Outside a receded
    /// range the incoming attributes pass through unchanged. The effective
    /// range never extends past the run, the storage color run, or the
    /// temporary-attribute run TextKit asked about.
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldUseTemporaryAttributes attrs: [NSAttributedString.Key: Any] = [:],
                       forDrawingToScreen toScreen: Bool, atCharacterIndex charIndex: Int,
                       effectiveRange effectiveCharRange: NSRangePointer?) -> [NSAttributedString.Key: Any]? {
        projectionHookCalls += 1
        guard toScreen, !recededCharacterRanges.isEmpty else { return attrs.isEmpty ? nil : attrs }
        var (receded, run) = recededRun(at: charIndex)
        if let effectiveCharRange, effectiveCharRange.pointee.length > 0,
           NSLocationInRange(charIndex, effectiveCharRange.pointee) {
            run = NSIntersectionRange(run, effectiveCharRange.pointee)
        }
        guard receded, let storage = layoutManager.textStorage, charIndex < storage.length else {
            if run.length > 0 { effectiveCharRange?.pointee = run }
            return attrs.isEmpty ? nil : attrs
        }
        var colorRange = NSRange(location: charIndex, length: 1)
        let base = storage.attribute(.foregroundColor, at: charIndex, effectiveRange: &colorRange) as? NSColor ?? .textColor
        run = NSIntersectionRange(run, colorRange)
        if run.length > 0 { effectiveCharRange?.pointee = run }
        let appearance = textView?.effectiveAppearance ?? NSAppearance.currentDrawing()
        var merged = attrs
        merged[.foregroundColor] = base.withAlphaComponent(Theme.recededSourceAlpha(appearance: appearance))
        return merged
    }
}
