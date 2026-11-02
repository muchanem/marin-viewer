import SwiftUI

struct SourceViewer: NSViewRepresentable {
    let buffer: SourceBuffer
    let fontSize: CGFloat
    let syntax: SyntaxSnapshot?
    let target: SourceLocation?
    let revision: Int
    let selectsTarget: Bool
    let focusRevision: Int
    let foldToDefinitionsRevision: Int
    let collapseFunctionsRevision: Int
    let highlightTarget: SourceLocation?
    let highlightRevision: Int
    /// Changes when the semantic index or the file's occurrence map changes.
    let semanticRevision: Int
    let semanticTarget: (Int) -> SemanticTarget?
    let occurrenceHighlightRanges: [Range<Int>]
    let activeOccurrenceHighlightRange: Range<Int>?
    /// The caret's function, faintly shaded behind everything else.
    let functionShadeRange: Range<Int>?
    /// Pull request line changes of this exact buffer (whole-line byte
    /// ranges) and which side they belong to; nil outside a review.
    var changedByteRanges: [Range<Int>] = []
    var changedLineRanges: [Range<Int>] = []
    var changeRevision: ReviewRevision? = nil
    var reviewIdentity: String? = nil
    var reviewFoldInput: ReviewFoldInput? = nil
    var refreshedViewport: SourceLocation? = nil
    /// The active presentation mode's projection for this exact buffer, or
    /// nil in Normal mode. Applied at draw time only.
    let projection: SourceProjection?
    /// The buffer's precomputed content identity, so a projection is matched
    /// exactly without hashing the file on every update.
    let sourceIdentity: SourceContentIdentity?
    /// Hide Tests' projection for this exact buffer, or nil. Hidden test code
    /// joins the fold union; the source bytes never change.
    var testCodePresentation: TestCodePresentation? = nil
    var onToggleTestRegion: (Int) -> Void = { _ in }
    let pinnedOccurrenceGroups: [PinnedOccurrenceGroup]
    let criticalityMenu: (Int) -> ReaderTextView.CriticalityMenu?
    /// Critical-mode hover and counts: generic presentation values; the
    /// reader and gutter know nothing about classification.
    let pointerSummariesEnabled: Bool
    let hoverPresentation: CriticalSummaryModel.HoverPresentation?
    let foldAnnotations: [String: CountAnnotation]
    let onPointerOverSource: (Int?) -> Void
    let onHoverNavigate: (SemanticPosition?, String) -> Void
    let onPopoverHover: (Bool) -> Void
    let onHoverDismiss: () -> Void
    let onSetSymbolCriticality: (String, Criticality?) -> Void
    let onSetPackageCriticality: (String, Criticality?) -> Void
    let onSelectOccurrences: (Int?) -> Void
    let onTogglePinnedOccurrences: (Int?) -> Void
    let onGoToDefinition: (Int) -> Void
    let onKeyboardGoToDefinition: (Int, Int) -> Void
    let onFindReferences: (Int) -> Void
    let onCaret: (Int) -> Void
    let onPosition: (Int, Int) -> Void

    func makeCoordinator() -> SourceViewerCoordinator { SourceViewerCoordinator() }

    func makeNSView(context: Context) -> SourceContainerView {
        let view = SourceContainerView()
        let scroll = view.scroll
        view.addSubview(scroll)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        let text = ReaderTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.isAutomaticLinkDetectionEnabled = false
        text.isAutomaticQuoteSubstitutionEnabled = false
        text.isAutomaticDashSubstitutionEnabled = false
        text.allowsUndo = false
        text.usesFindBar = true
        text.isIncrementalSearchingEnabled = true
        text.textContainerInset = NSSize(width: Theme.sourceInset, height: Theme.sourceInset)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = true
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.autoresizingMask = [.width]
        text.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = false
        text.setAccessibilityLabel("Read-only source code")
        text.delegate = context.coordinator
        text.layoutManager?.delegate = context.coordinator
        scroll.documentView = text
        let ruler = LineNumberGutter(textView: text)
        view.gutter = ruler
        view.addSubview(ruler)
        context.coordinator.gutter = ruler
        context.coordinator.textView = text
        context.coordinator.scrollView = scroll
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(SourceViewerCoordinator.didScroll), name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        return view
    }

    func updateNSView(_ view: SourceContainerView, context: Context) {
        let scroll = view.scroll
        let coordinator = context.coordinator
        guard let text = coordinator.textView else { return }
        coordinator.onPosition = onPosition
        coordinator.onCaret = onCaret
        coordinator.updating = true
        defer { coordinator.updating = false }
        if let reader = text as? ReaderTextView {
            reader.semanticTarget = semanticTarget
            reader.onSelectOccurrences = onSelectOccurrences
            reader.onTogglePinnedOccurrences = onTogglePinnedOccurrences
            reader.onGoToDefinition = onGoToDefinition
            reader.onKeyboardGoToDefinition = onKeyboardGoToDefinition
            reader.onToggleEnclosingFunction = { [weak coordinator] byte in coordinator?.toggleFunction(at: byte) ?? false }
            reader.onFindReferences = onFindReferences
            reader.criticalityMenu = criticalityMenu
            reader.pointerSummariesEnabled = pointerSummariesEnabled
            reader.onPointerOverSource = onPointerOverSource
            reader.onHoverNavigate = onHoverNavigate
            reader.onPopoverHover = onPopoverHover
            reader.onHoverDismiss = onHoverDismiss
            reader.onSetSymbolCriticality = onSetSymbolCriticality
            reader.onSetPackageCriticality = onSetPackageCriticality
            reader.onToggleTestRegion = onToggleTestRegion
            reader.byteForUTF16 = { [buffer] in buffer.byteOffset(forUTF16: $0) }
            reader.utf16RangeForBytes = { [buffer] in buffer.utf16Range(forByteRange: $0) }
            reader.occurrenceHighlightRanges = occurrenceHighlightRanges.map(buffer.utf16Range(forByteRange:))
            reader.functionShadeRange = functionShadeRange.map(buffer.utf16Range(forByteRange:))
            reader.changedCharacterRanges = changedByteRanges.map(buffer.utf16Range(forByteRange:))
            reader.changeRevision = changeRevision
            reader.activeOccurrenceHighlightRange = activeOccurrenceHighlightRange.map(buffer.utf16Range(forByteRange:))
            reader.pinnedOccurrenceDecorations = pinnedOccurrenceGroups.map { group in
                ReaderTextView.PinnedDecoration(ranges: group.byteRanges.map(buffer.utf16Range(forByteRange:)),
                                                colorSlot: group.colorSlot)
            }
            let pinnedCount = pinnedOccurrenceGroups.reduce(0) { $0 + $1.byteRanges.count }
            let transientCount = occurrenceHighlightRanges.count
            var help: String
            if pinnedCount > 0 {
                help = "\(pinnedOccurrenceGroups.count) pinned symbol groups, \(pinnedCount) pinned occurrences. Double-click a pinned occurrence to unlock it."
            } else if transientCount > 0 {
                help = "\(transientCount) occurrences highlighted. Double-click to pin this symbol."
            } else {
                help = "Read-only source code. Double-click a symbol to pin its occurrences."
            }
            let hiddenTests = testCodePresentation?.hiddenRegions.count ?? 0
            help += " Press x to expand or collapse the function at the caret."
            if hiddenTests > 0 {
                help += " \(hiddenTests) test \(hiddenTests == 1 ? "region is" : "regions are") hidden; click a region's label or gutter control to show it."
            }
            reader.setAccessibilityHelp(help)
            if coordinator.semanticRevision != semanticRevision {
                coordinator.semanticRevision = semanticRevision
                reader.clearHover()
            }
        }
        let changed = coordinator.buffer?.path != buffer.path || coordinator.buffer?.data != buffer.data
            || coordinator.buffer?.revision != buffer.revision || coordinator.reviewIdentity != reviewIdentity
        coordinator.reviewIdentity = reviewIdentity
        let syntaxChanged = coordinator.syntax != syntax
        // Bound to these exact bytes; converted after any source replacement below.
        let testsChanged = coordinator.setTestPresentation(
            testCodePresentation?.matches(path: buffer.path, sourceIdentity: sourceIdentity) == true ? testCodePresentation : nil)
        let appliedDefaultFolds = coordinator.updateSyntax(syntax, buffer: buffer, resetFolds: changed)
        let bulkFoldsChanged = coordinator.consumeFoldCommands(definitions: foldToDefinitionsRevision, functions: collapseFunctionsRevision)
        let topCharacter = !changed && coordinator.revision == revision
            && (appliedDefaultFolds || (reviewFoldInput != nil && coordinator.reviewDefaultsPending))
            ? coordinator.visibleTopCharacter() : nil
        let reviewFoldsChanged = coordinator.applyInitialReviewFolds(reviewFoldInput, sourceIdentity: sourceIdentity)
        // Replacing attributes can reset TextKit's selection even for the
        // same source. Keep the caret for late syntax and font updates.
        let selection = text.selectedRange()
        let selectedByte = buffer.byteOffset(forUTF16: selection.location)
        // Apply once per visit, including syntax arriving after a file loads.
        // Ordinary updates must preserve functions the reader manually folds.
        let expandsTargetFunction = selectsTarget && target?.path == buffer.path
            && (changed || coordinator.revision != revision || appliedDefaultFolds)
        var appliedFoldLayout = false
        if changed || syntaxChanged || text.font?.pointSize != fontSize {
            if changed { coordinator.cancelDestinationHighlight() }
            (text as? ReaderTextView)?.clearHover()
            let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = max(Theme.sourceLineHeight, fontSize * 1.55)
            paragraph.maximumLineHeight = paragraph.minimumLineHeight
            paragraph.tabStops = []
            paragraph.defaultTabInterval = font.maximumAdvancement.width * 4
            let attributed = NSMutableAttributedString(string: buffer.text, attributes: [.font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph])
            if syntax?.path == buffer.path {
                for highlight in syntax?.highlights ?? [] {
                    let range = buffer.utf16Range(forByteRange: highlight.byteRange)
                    guard range.location + range.length <= attributed.length else { continue }
                    attributed.addAttribute(.foregroundColor, value: Theme.SyntaxColors.color(for: highlight.name), range: range)
                }
            }
            if changed { coordinator.prepareForSourceReplacement() }
            text.textStorage?.setAttributedString(attributed)
            if changed { coordinator.finishSourceReplacement() }
            text.font = font
            text.backgroundColor = .textBackgroundColor
            if let ruler = view.gutter {
                ruler.buffer = buffer
                ruler.fontSize = fontSize
                ruler.folds = syntax?.folds ?? []
                ruler.onToggleFold = { [weak coordinator] fold in coordinator?.toggleFold(fold) }
                ruler.onToggleTestRegion = onToggleTestRegion
            }
            // Resolve default folds against a pending/restored destination
            // before asking TextKit to generate any folded glyphs. Applying
            // one fold layout and immediately invalidating it again to reveal
            // the destination can re-enter NSATSTypesetter on large files.
            if changed || coordinator.revision != revision || appliedDefaultFolds {
                let byte = changed || coordinator.revision != revision
                    ? (target?.path == buffer.path ? target?.byteOffset ?? 0 : 0)
                    : selectedByte
                coordinator.reveal(byteOffset: byte, expandFunction: expandsTargetFunction, applyAttributes: false)
                if let viewport = refreshedViewport, viewport.path == buffer.path, viewport.revision == buffer.revision {
                    coordinator.reveal(byteOffset: viewport.byteOffset, applyAttributes: false)
                }
            }
            coordinator.applyFoldAttributes()
            if !changed { text.setSelectedRange(selection) }
            appliedFoldLayout = true
        } else if testsChanged || reviewFoldsChanged || bulkFoldsChanged {
            // Hide Tests toggled or a region was revealed: reveal any fold
            // around a new target first, then apply one combined layout.
            if coordinator.revision != revision {
                coordinator.reveal(byteOffset: target?.path == buffer.path ? target?.byteOffset ?? 0 : 0,
                                   expandFunction: expandsTargetFunction, applyAttributes: false)
            }
            view.gutter?.onToggleTestRegion = onToggleTestRegion
            coordinator.applyFoldAttributes()
            appliedFoldLayout = true
        }
        if changed || coordinator.revision != revision {
            coordinator.revision = revision
            coordinator.cancelDestinationHighlight()
            (text as? ReaderTextView)?.clearHover()
            let byte = target?.path == buffer.path ? target?.byteOffset ?? 0 : 0
            let range = NSRange(location: buffer.utf16Offset(forByte: byte), length: 0)
            // The changed/syntax/font branch already revealed this target and
            // generated the folded glyph tree. Invalidating the same large
            // document again in this update can re-enter NSATSTypesetter and
            // corrupt its glyph-to-character mapping.
            coordinator.reveal(byteOffset: byte, expandFunction: expandsTargetFunction, applyAttributes: !appliedFoldLayout)
            if selectsTarget { text.setSelectedRange(range) }
            if let viewport = refreshedViewport, viewport.path == buffer.path, viewport.revision == buffer.revision {
                coordinator.preserveViewport(atCharacter: buffer.utf16Offset(forByte: viewport.byteOffset))
            } else {
                coordinator.programmaticPositionByte = byte
                scroll.pendingLocation = range.location
                scroll.needsLayout = true
                coordinator.settleNavigation(atUTF16: range.location, revision: revision)
            }
        }
        if !changed, (reviewFoldsChanged || appliedDefaultFolds), let topCharacter {
            coordinator.preserveViewport(atCharacter: topCharacter)
        }
        // The projection is bound to exact bytes; a stale one for another
        // file or older contents is never applied. Source replacement above
        // already cleared the previous ranges.
        coordinator.applyProjection(projection?.matches(path: buffer.path, sourceIdentity: sourceIdentity) == true ? projection : nil,
                                    buffer: buffer)
        if let reader = text as? ReaderTextView {
            // A presentation for other bytes (file or index changed under it) never shows.
            reader.hoverPresentation = changed ? nil : hoverPresentation
        }
        if let ruler = view.gutter {
            if ruler.changedLines != changedLineRanges || ruler.changeRevision != changeRevision {
                ruler.changedLines = changedLineRanges
                ruler.changeRevision = changeRevision
                ruler.needsDisplay = true
            }
            if ruler.annotations != foldAnnotations || ruler.showsAnnotations != pointerSummariesEnabled {
                ruler.annotations = foldAnnotations
                ruler.showsAnnotations = pointerSummariesEnabled
                ruler.needsDisplay = true
            }
        }
        if coordinator.highlightRevision != highlightRevision {
            coordinator.highlightRevision = highlightRevision
            if highlightTarget?.path == buffer.path, let byte = highlightTarget?.byteOffset {
                coordinator.flashDestination(atUTF16: buffer.utf16Offset(forByte: byte))
            }
        }
        if coordinator.focusRevision != focusRevision {
            coordinator.focusRevision = focusRevision
            DispatchQueue.main.async { [weak text] in
                guard let text, let window = text.window else { return }
                window.makeFirstResponder(text)
            }
        }
        view.gutter?.needsDisplay = true
        text.needsDisplay = true
    }

    static func dismantleNSView(_ view: SourceContainerView, coordinator: SourceViewerCoordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }
}
