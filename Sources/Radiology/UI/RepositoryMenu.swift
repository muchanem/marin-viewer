import SwiftUI

/// Repository identity and repository-opening actions share one native menu.
struct RepositoryMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button("Open Repository…", systemImage: "folder.badge.plus", action: model.chooseRepository)
            Menu("Open Recent") {
                ForEach(model.recentRepositories, id: \.self) { path in
                    Button(path) { model.openRepository(URL(filePath: path)) }
                }
            }
            .disabled(model.recentRepositories.isEmpty)
        } label: {
            Text(title)
                .font(Theme.Fonts.body.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140)
        }
        .menuIndicator(.visible)
        .help(model.attachedRoot?.path ?? "Open a repository (⌘O)")
        .accessibilityLabel("Repository: \(title)")
    }

    private var title: String {
        model.attachedRoot?.lastPathComponent ?? model.repository?.root.lastPathComponent ?? "Repository"
    }
}
