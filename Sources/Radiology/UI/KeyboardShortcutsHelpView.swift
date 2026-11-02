import SwiftUI

/// The bundled help document is also readable in the repository. Rendering its
/// short paragraphs separately preserves heading hierarchy and inline key names.
struct KeyboardShortcutsHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var paragraphs: [String] = []
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.inset) {
            Text("Keyboard Shortcuts").font(Theme.Fonts.heading)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.inset) {
                    ForEach(paragraphs.indices, id: \.self) { index in
                        let paragraph = paragraphs[index]
                        if paragraph.hasPrefix("## ") {
                            Text(String(paragraph.dropFirst(3)))
                                .font(Theme.Fonts.heading).accessibilityAddTraits(.isHeader)
                                .padding(.top, Theme.spacing)
                        } else {
                            Text(.init(paragraph)).font(Theme.Fonts.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if let error { Text(error).font(Theme.Fonts.body) }
                }
                .textSelection(.enabled)
                .padding(.trailing, Theme.inset)
            }
            HStack {
                Spacer()
                Button("Done", action: dismiss.callAsFunction).keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.inset * 2).frame(width: 640, height: 560)
        .task { loadDocument() }
    }

    private func loadDocument() {
        do {
            guard let url = Bundle.module.url(forResource: "KeyboardShortcuts", withExtension: "md", subdirectory: "Help") else {
                throw BrowserError.message("The keyboard reference is missing from this app bundle.")
            }
            paragraphs = try String(contentsOf: url, encoding: .utf8)
                .components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("# ") }
        } catch { self.error = error.localizedDescription }
    }
}
