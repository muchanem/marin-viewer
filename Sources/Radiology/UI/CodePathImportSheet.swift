import SwiftUI
import UniformTypeIdentifiers

struct CodePathImportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    @State private var isChoosingFile = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.inset) {
            Text("Import Code Path").font(Theme.Fonts.heading)
            Text("First line: a title. Then one file:function:description per line.")
                .font(Theme.Fonts.body)
            TextEditor(text: $text)
                .font(Theme.Fonts.codePreview)
                .focused($isFocused)
                .border(.separator)
                .accessibilityLabel("Code path text")
            Text(verbatim: "Use repository-relative paths and function names. Escape colons in function names as \\:; descriptions may contain colons.")
                .font(Theme.Fonts.meta).foregroundStyle(.secondary)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.Fonts.meta).foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Choose Text File…", action: chooseFile)
                Spacer()
                Button("Cancel", action: dismiss.callAsFunction).keyboardShortcut(.cancelAction)
                Button("Import", action: importText).keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.canImportCodePath)
            }
        }
        .padding(Theme.inset * 2)
        .frame(width: 620, height: 440)
        .task { isFocused = true }
        .onChange(of: model.codePaths.repositoryPath) { dismiss() }
        .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: [.text], onCompletion: loadFile)
    }

    private func chooseFile() { isChoosingFile = true }

    private func loadFile(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0 <= CodePathParser.maximumBytes else {
                throw BrowserError.message("Code paths must be no larger than 2 MB.")
            }
            text = try String(contentsOf: url, encoding: .utf8)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func importText() {
        do { try model.importCodePath(text) }
        catch { self.error = error.localizedDescription }
    }
}
