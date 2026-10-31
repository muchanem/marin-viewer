import SwiftUI

struct IndexingPersonalityPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var semantics = model.semantics
        VStack(alignment: .leading, spacing: Theme.spacing / 2) {
            HStack(alignment: .firstTextBaseline) {
                Picker("Personality", selection: $semantics.personality) {
                    ForEach(IndexingPersonality.allCases) { personality in
                        Text(personality.name).tag(personality)
                    }
                }
                .pickerStyle(.menu)
                .font(Theme.Fonts.body)
                .disabled(!semantics.isRepositoryOpen)
                .help("Remembered for this repository. Changing personality starts its index.")
                Spacer()
                Button("Show Settings File") {
                    let url = semantics.personalitySettings?.url
                        ?? IndexingPersonalityStore.directory.appending(path: semantics.personality.rawValue + ".toml")
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .buttonStyle(.link)
                .font(Theme.Fonts.meta)
                .disabled(!semantics.isRepositoryOpen)
            }
            Text(semantics.personalitySettings?.summary ?? semantics.personality.summary)
                .font(Theme.Fonts.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
