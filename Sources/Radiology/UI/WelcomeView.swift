import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(spacing: Theme.inset * 2) {
            ContentUnavailableView {
                Label("Read the Code", systemImage: "doc.text.magnifyingglass")
            } description: {
                Text("Open a repository to browse, search, and follow the source.\nYou can also drop a folder here.")
            } actions: {
                Button("Open Repository…", action: model.chooseRepository).keyboardShortcut("o").buttonStyle(.borderedProminent)
            }.fixedSize(horizontal: false, vertical: true)
            if !model.recentRepositories.isEmpty {
                VStack(alignment: .leading, spacing: Theme.spacing) {
                    Text("Recent Repositories").font(Theme.Fonts.heading)
                    ForEach(model.recentRepositories, id: \.self) { path in
                        Button { model.openRepository(URL(filePath: path)) } label: {
                            Label(path, systemImage: "folder").lineLimit(1).truncationMode(.middle)
                        }.buttonStyle(.link)
                    }
                }.frame(maxWidth: 500).padding(Theme.inset)
            }
            Text("⌘K  Go to file     ⇧⌘F  Search     ⌘[  Go back")
                .font(Theme.Fonts.meta).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
