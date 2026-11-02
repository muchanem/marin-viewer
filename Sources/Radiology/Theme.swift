import SwiftUI

/// Native UI uses semantic SF styles; the source surface uses adjustable SF Mono.
enum Theme {
    static let windowMinWidth: CGFloat = 760
    static let windowMinHeight: CGFloat = 480
    static let windowDefaultWidth: CGFloat = 1180
    static let windowDefaultHeight: CGFloat = 780
    static let sidebarMinWidth: CGFloat = 220
    static let sidebarIdealWidth: CGFloat = 280
    static let sidebarMaxWidth: CGFloat = 440
    static let inset: CGFloat = 12
    static let spacing: CGFloat = 8
    static let sourceFontSize: CGFloat = 14
    static let sourceLineHeight: CGFloat = 22
    static let sourceInset: CGFloat = 12
    /// A compact disclosure lane and sparse canonical numbers. Fold badges
    /// share the remaining space; tooltips retain counts when a badge won't fit.
    static let gutterWidth: CGFloat = 72
    static let gutterInset: CGFloat = 6
    static let foldMarkerSize: CGFloat = 11
    static let foldHitWidth: CGFloat = 20
    static let inspectorMinWidth: CGFloat = 220
    static let inspectorIdealWidth: CGFloat = 280
    static let inspectorMaxWidth: CGFloat = 420
    /// Both panes stay usable while their native divider moves.
    static let inspectorReferencesMinHeight: Double = 150
    static let inspectorDefinitionMinHeight: Double = 100
    static let inspectorBookmarksMinHeight: Double = 100
    static let inspectorImplementationRowHeight: CGFloat = 22
    static let contextHeaderHeight: CGFloat = 28
    /// Leading lane for row disclosure triangles in the Context inspector.
    static let disclosureWidth: CGFloat = 14
    static let snippetLineNumberWidth: CGFloat = 30
    static let snippetCornerRadius: CGFloat = 6
    static let outlineIndent: CGFloat = 12
    static let callerPillHorizontalInset: CGFloat = 12
    static let callerPillVerticalInset: CGFloat = 6
    /// Critical-mode hover popover width and row bound.
    static let hoverPopoverWidth: CGFloat = 380
    static let maxHoverRows = 8
    static let breadcrumbSpacing: CGFloat = 5
    static let breadcrumbHeight: CGFloat = 32
    /// The toolbar's Before/After picker keeps enough room for both labels.
    static let revisionPickerWidth: CGFloat = 136
    static let changeCountMinWidth: CGFloat = 64
    static let destinationHighlightAlpha: CGFloat = 0.18
    /// The read-only source caret: a thin steady bar in the system's dynamic
    /// insertion-point color (accent-tinted, adapts to light and dark),
    /// slightly softened so it reads as a position marker, not an edit cursor.
    static let sourceCaretWidth: CGFloat = 1.5
    /// The caret's function: a barely-there wash of the label color, so it is
    /// neutral in any accent and reads in both appearances. Lighter than the
    /// current-line tint (accent at 5%), which stays visible on top of it.
    static func functionShadeColor(appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.labelColor.withAlphaComponent(dark ? 0.045 : 0.03)
    }
    static var sourceCaretColor: NSColor { NSColor.textInsertionPointColor.withAlphaComponent(0.85) }
    /// Pull request line changes: added lines (After) in green, removed
    /// lines (Before) in red. The wash sits with the function shade at the
    /// bottom of the source layers; the gutter bar is 3 points wide.
    static let changeBarWidth: CGFloat = 3
    static func changeWashColor(revision: ReviewRevision, appearance: NSAppearance) -> NSColor {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let base: NSColor = revision == .after ? .systemGreen : .systemRed
        return base.withAlphaComponent(dark ? 0.14 : 0.10)
    }
    static func changeBarColor(revision: ReviewRevision) -> NSColor {
        (revision == .after ? NSColor.systemGreen : NSColor.systemRed).withAlphaComponent(0.6)
    }
    /// Receded source in a projection (Critical mode's non-call source and ordinary calls):
    /// the token keeps its syntax color and loses opacity, never weight.
    /// Dark surfaces need a little more opacity for the same perceived
    /// recession, so each appearance is tuned separately.
    static func recededSourceAlpha(appearance: NSAppearance) -> CGFloat {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? 0.38 : 0.30
    }
    enum Fonts {
        static let body = Font.body
        static let heading = Font.headline
        static let meta = Font.callout
        /// Secondary Changes-row paths/counts; filenames stay at native body size.
        static let changeDetail = Font.caption
        static let changeStatus = Font.caption.monospaced().weight(.semibold)
        static let codePreview = Font.body.monospaced()
        /// Canonical symbol identifiers and command lines: long, secondary, monospaced.
        static let identifier = Font.caption.monospaced()
        /// Context inspector region labels: small, semibold, secondary.
        static let regionTitle = Font.caption.weight(.semibold)
        static let inspectorSymbol = Font.title3.weight(.semibold)
        static let inspectorMetadata = Font.caption
        /// Signatures, call sites, and definition previews in the inspector:
        /// one step below body so code fits the column without competing
        /// with the semibold symbol name.
        static let codeSnippet = Font.callout.monospaced()
        static let codeSnippetEmphasis = Font.callout.monospaced().weight(.semibold)
        static let snippetLineNumber = Font.caption.monospacedDigit()
        /// Row disclosure triangles: small and secondary, like Finder's.
        static let disclosure = Font.caption2.weight(.semibold)

    }
    static let semanticUnderlineColor = NSColor.controlAccentColor
    static let semanticOccurrenceColor = NSColor.controlAccentColor.withAlphaComponent(0.16)
    static let activeSemanticOccurrenceColor = NSColor.controlAccentColor.withAlphaComponent(0.28)

    struct PinnedOccurrenceColors {
        let fill: NSColor
        let stroke: NSColor
    }

    /// Teal, amber, violet, and rose remain distinguishable from the ordinary
    /// blue accent wash. Locked groups also receive a heavier outline, so hue
    /// is never the only state cue. System colors adapt their actual RGB values
    /// while opacity is tuned separately for light and dark source surfaces.
    static func pinnedOccurrenceColors(slot: Int, appearance: NSAppearance) -> PinnedOccurrenceColors {
        let palette: [NSColor] = [.systemTeal, .systemOrange, .systemPurple, .systemPink]
        let base = palette[((slot % palette.count) + palette.count) % palette.count]
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return PinnedOccurrenceColors(fill: base.withAlphaComponent(dark ? 0.22 : 0.15),
                                      stroke: base.withAlphaComponent(dark ? 0.88 : 0.72))
    }

    /// Maps Tree-sitter capture names to Atom's One Light syntax palette
    /// (atom/one-light-syntax, styles/colors.less and syntax/_base.less). The
    /// Marin viewer is light-only, so the colors are fixed. One Light's red
    /// (variables, `self`, tags) is left out: `self` takes the orange One Light
    /// gives Python parameters, and tags take the function blue. Roles are keyed
    /// on the capture's first component, with whole-name exceptions where One
    /// Light distinguishes a sub-scope.
    enum SyntaxColors {
        static let text = rgb(0x383A42)        // mono-1
        static let comment = rgb(0xA0A1A7)     // mono-3
        static let cyan = rgb(0x0184BC)        // hue-1: escapes, builtins
        static let blue = rgb(0x4078F2)        // hue-2: functions
        static let purple = rgb(0xA626A4)      // hue-3: keywords
        static let green = rgb(0x50A14F)       // hue-4: strings
        static let orange = rgb(0x986801)      // hue-6: numbers, constants, parameters
        static let typeOrange = rgb(0xC18401)  // hue-6-2: types and classes

        static func color(for capture: String) -> NSColor {
            switch capture {
            case "string.escape", "string.special", "string.regexp": cyan
            case "type.builtin", "function.builtin": cyan
            case "variable.builtin", "variable.parameter": orange
            case "comment.documentation": comment
            default: role(of: capture)
            }
        }

        private static func role(of capture: String) -> NSColor {
            switch capture.split(separator: ".").first {
            case "comment": comment
            case "string": green
            case "number", "constant": orange
            case "keyword": purple
            case "type", "constructor", "namespace": typeOrange
            case "function", "attribute", "tag": blue
            default: text
            }
        }

        private static func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }
}
