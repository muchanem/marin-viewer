import SwiftUI
import ViewerCore

/// Wordbase text with backticked code set in the monospaced face on the
/// demo's soft fill.
enum InlineCodeText {
    static func attributed(_ string: String, codeFont: Font) -> AttributedString {
        var output = AttributedString()
        for (index, part) in string.components(separatedBy: "`").enumerated() {
            var piece = AttributedString(part)
            if index % 2 == 1 {
                piece.font = codeFont
                piece.backgroundColor = Color(nsColor: DiffReaderStyle.soft)
            }
            output += piece
        }
        return output
    }
}

/// A layered description (DESIGN.md §2): the sentence, then on request the
/// paragraph and the long form. "More" opens the next layer, "Full
/// description" the third, "Less" closes back to the sentence.
struct LayeredDescriptionText: View {
    enum Style {
        /// The step header: paragraphs stacked, the control on its own line.
        case block
        /// A file header: one run of text with the control inline after it.
        case inline
    }

    let layers: Layers
    let level: Int
    let style: Style
    let setLevel: (Int) -> Void

    private var maxLevel: Int {
        if let l3 = layers.l3, !l3.isEmpty { return 3 }
        if let l2 = layers.l2, !l2.isEmpty { return 2 }
        return 1
    }

    private var control: (title: String, level: Int)? {
        guard maxLevel > 1 else { return nil }
        if level < maxLevel { return (level == 1 ? "More" : "Full description", level + 1) }
        return ("Less", 1)
    }

    var body: some View {
        switch style {
        case .block: block
        case .inline: inline
        }
    }

    private var block: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(InlineCodeText.attributed(layers.l1, codeFont: .callout.monospaced()))
                .font(.body)
                .foregroundStyle(Color(nsColor: DiffReaderStyle.ink))
                .fixedSize(horizontal: false, vertical: true)
            if level >= 2, let l2 = layers.l2, !l2.isEmpty {
                Text(InlineCodeText.attributed(l2, codeFont: .callout.monospaced()))
                    .foregroundStyle(Color(nsColor: DiffReaderStyle.headerDescription))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if level >= 3 {
                ForEach(Array((layers.l3 ?? []).enumerated()), id: \.offset) { _, paragraph in
                    Text(InlineCodeText.attributed(paragraph, codeFont: .callout.monospaced()))
                        .foregroundStyle(Color(nsColor: DiffReaderStyle.headerDescription))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let control {
                Button(control.title) { setLevel(control.level) }
                    .buttonStyle(.link)
                    .font(.callout)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    private static let controlURL = URL(string: "marin-viewer-layer:next")!

    private var inline: some View {
        var text = InlineCodeText.attributed(layers.l1, codeFont: .callout.monospaced())
        if level >= 2, let l2 = layers.l2, !l2.isEmpty {
            text += AttributedString(" ") + InlineCodeText.attributed(l2, codeFont: .callout.monospaced())
        }
        if let control {
            var link = AttributedString(" " + control.title)
            link.link = Self.controlURL
            link.foregroundColor = Color(nsColor: DiffReaderStyle.accent)
            text += link
        }
        return Text(text)
            .font(.callout)
            .foregroundStyle(Color(nsColor: DiffReaderStyle.headerDescription))
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.openURL, OpenURLAction { _ in
                if let control { setLevel(control.level) }
                return .handled
            })
    }
}
