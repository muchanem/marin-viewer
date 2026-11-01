import SwiftUI

/// The viewer's few colors beyond the system's, from the demo's palette. The app is light mode
/// only (DESIGN.md §5), so these are plain values.
extension Color {
    static let viewerInk = Color(red: 0x1b / 255, green: 0x21 / 255, blue: 0x29 / 255)
    static let viewerMuted = Color(red: 0x67 / 255, green: 0x71 / 255, blue: 0x80 / 255)
    static let viewerRule = Color(red: 0xdf / 255, green: 0xe3 / 255, blue: 0xe8 / 255)
    static let viewerSoft = Color(red: 0xee / 255, green: 0xf1 / 255, blue: 0xf5 / 255)
    static let viewerBackground = Color(red: 0xf4 / 255, green: 0xf6 / 255, blue: 0xf8 / 255)
    static let viewerAccent = Color(red: 0x1f / 255, green: 0x56 / 255, blue: 0xa8 / 255)
    static let viewerAccentSoft = Color(red: 0xe6 / 255, green: 0xee / 255, blue: 0xfb / 255)
    static let viewerNote = Color(red: 0xa8 / 255, green: 0x65 / 255, blue: 0x0b / 255)
    static let viewerNoteSoft = Color(red: 0xfd / 255, green: 0xf3 / 255, blue: 0xe2 / 255)
    static let viewerOK = Color(red: 0x2f / 255, green: 0x7a / 255, blue: 0x3d / 255)
    static let viewerBad = Color(red: 0xb0 / 255, green: 0x3a / 255, blue: 0x3a / 255)
    static let viewerStateFill = Color(red: 0xec / 255, green: 0xe6 / 255, blue: 0xf8 / 255)
    static let viewerStateInk = Color(red: 0x5b / 255, green: 0x3a / 255, blue: 0x9a / 255)
    // Diagram strokes and fills.
    static let diagramStroke = Color(red: 0xb9 / 255, green: 0xc2 / 255, blue: 0xce / 255)
    static let diagramEdge = Color(red: 0x9a / 255, green: 0xa5 / 255, blue: 0xb3 / 255)
    static let diagramGroupFill = Color(red: 0xf7 / 255, green: 0xf9 / 255, blue: 0xfb / 255)
    static let diagramCodeFill = Color(red: 0xfb / 255, green: 0xfc / 255, blue: 0xfe / 255)
    static let diagramTouchedFill = Color(red: 0xff / 255, green: 0xf6 / 255, blue: 0xe5 / 255)
}

/// Type for the viewer's own surfaces. Body text stays at the system body size like Radiology's
/// sidebars; card titles and section labels are small and semibold, and metadata is one step
/// down in secondary color, so weight carries the hierarchy rather than size.
enum ViewerFonts {
    /// Card headers ("This PR", "In Marin", "Inside this PR") and panel section labels.
    static let cardTitle = Font.caption.weight(.semibold)
    /// The PR title in the description card.
    static let prTitle = Font.headline
    /// Step titles in the Code path tab and the placeholder.
    static let stepTitle = Font.body.weight(.medium)
    static let body = Font.body
    /// One-sentence descriptions under titles.
    static let summary = Font.callout
    static let meta = Font.caption
    static let mono = Font.caption.monospaced()
    /// Pills: state, status, severity, "moved by session".
    static let pill = Font.caption2.weight(.semibold)
}

/// A small capsule label: PR state, note status and severity.
struct ViewerPill: View {
    let text: String
    var fill: Color = .viewerSoft
    var ink: Color = .viewerMuted

    var body: some View {
        Text(text)
            .font(ViewerFonts.pill)
            .foregroundStyle(ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(fill, in: .capsule)
            .fixedSize()
    }
}

/// The viewer's card container in the top strip.
struct ViewerCard<Header: View, Content: View>: View {
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.viewerRule) }
    }
}
