import AppKit
import SwiftUI

/// Metrics and colours of the diff reader, taken from the demo's main view
/// (`demo/index.html`: `.ln`, `.gap`, `.inline-note`, `.fhead`). The viewer
/// is light only, so the colours are fixed values. Code uses the system
/// monospaced face and Radiology's syntax colours; interface text uses
/// semantic SF styles.
enum DiffReaderStyle {
    // MARK: Code rows

    static let codeFontSize: CGFloat = 12
    /// The demo's 19 px row at 12 px, kept proportional when the size changes.
    static func lineHeight(fontSize: CGFloat) -> CGFloat { (fontSize * 19 / 12).rounded() }
    static func codeFont(size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size, weight: .regular) }
    /// Line numbers: one point under the code, with tabular digits.
    static func numberFont(size: CGFloat) -> NSFont { .monospacedDigitSystemFont(ofSize: size - 1, weight: .regular) }
    static let codeLeading: CGFloat = 4
    static let codeTrailing: CGFloat = 24

    // MARK: Gutter

    static let numberColumnWidth: CGFloat = 44
    static let markerColumnWidth: CGFloat = 16
    static let numberTrailingPadding: CGFloat = 8
    static let blameColumnWidth: CGFloat = 156
    static let blameHorizontalPadding: CGFloat = 8
    static let noteDotDiameter: CGFloat = 9
    static func gutterWidth(blame: Bool) -> CGFloat {
        (blame ? blameColumnWidth : 0) + numberColumnWidth * 2 + markerColumnWidth
    }

    // MARK: Gap bars and inline notes

    static let gapHeight: CGFloat = 25
    static let gapButtonSpacing: CGFloat = 12
    static let interfaceFontSize: CGFloat = 11.5
    static let noteMaxWidth: CGFloat = 760
    static let noteOuterTop: CGFloat = 4
    static let noteOuterBottom: CGFloat = 8
    static let noteOuterTrailing: CGFloat = 12
    static let notePaddingHorizontal: CGFloat = 10
    static let notePaddingVertical: CGFloat = 7
    static let noteLineSpacing: CGFloat = 2
    static let noteCornerRadius: CGFloat = 6

    // MARK: Cards

    static let cardCornerRadius: CGFloat = 8
    static let cardSpacing: CGFloat = 12
    static let readerHorizontalInset: CGFloat = 16
    static let readerTopInset: CGFloat = 12
    static let readerBottomInset: CGFloat = 80
    static let flashDuration: TimeInterval = 1.6

    // MARK: Colours (demo tokens)

    static let background = rgb(0xF4F6F8)
    static let pane = NSColor.white
    static let ink = rgb(0x1B2129)
    static let muted = rgb(0x677180)
    static let rule = rgb(0xDFE3E8)
    static let soft = rgb(0xEEF1F5)
    static let accent = rgb(0x1F56A8)
    static let accentSoft = rgb(0xE6EEFB)
    static let added = rgb(0xE7F5EA)
    static let addedStrong = rgb(0xC9EBD1)
    static let addedNumber = rgb(0x4F7D59)
    static let deleted = rgb(0xFBEAEA)
    static let deletedStrong = rgb(0xF3CCCC)
    static let deletedNumber = rgb(0x95595A)
    static let lineNumber = rgb(0xA0A8B3)
    static let gapFill = rgb(0xF1F5FB)
    static let gapRule = rgb(0xE3EAF5)
    static let note = rgb(0xA8650B)
    static let noteSoft = rgb(0xFDF3E2)
    static let noteRule = rgb(0xF0D7AB)
    static let resolvedDot = rgb(0x9AA5B3)
    static let flash = rgb(0xFFF1CF)
    static let headerFill = rgb(0xFAFBFC)
    static let headerDescription = rgb(0x3A4350)
    static let ok = rgb(0x2F7A3D)
    static let bad = rgb(0xB03A3A)

    /// An sRGB colour from a demo hex token.
    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
