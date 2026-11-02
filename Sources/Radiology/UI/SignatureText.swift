import SwiftUI

/// A declaration's source signature at a fixed line limit, reporting its
/// natural height so `ViewThatFits` can choose how many lines fit.
struct SignatureText: View {
    let signature: String
    let lineLimit: Int

    var body: some View {
        Text(signature)
            .font(Theme.Fonts.codeSnippet)
            .foregroundStyle(.primary)
            .lineLimit(lineLimit)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .help(signature)
            .accessibilityLabel("Signature")
            .accessibilityValue(signature)
    }
}
