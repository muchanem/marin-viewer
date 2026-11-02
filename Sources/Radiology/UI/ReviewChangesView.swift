import SwiftUI

/// The pull request's changed files: status, path, and quiet line counts.
/// Deleted files open their Before document; everything else opens After
/// (or the reader's current choice for that path).
struct ReviewChangesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?

    var body: some View {
        if let review = model.review {
            let presentation = ReviewChangesPresentation(changes: review.changes, filters: model.sourceFilters)
            VStack(spacing: 0) {
                Text(review.title).font(Theme.Fonts.body).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.inset)
                    .padding(.top, Theme.inset)
                    .padding(.bottom, Theme.spacing)
                HStack(spacing: Theme.spacing) {
                    Text("#\(review.number) · \(review.summary.stateTitle)")
                    Spacer(minLength: 0)
                    Text("+\(presentation.additions) −\(presentation.deletions)").monospacedDigit()
                        .fixedSize(horizontal: true, vertical: false)
                        .help("Totals for visible text-file changes; binary line counts are unavailable.")
                }
                .font(Theme.Fonts.meta).foregroundStyle(.secondary)
                .padding(.horizontal, Theme.inset)
                .padding(.bottom, Theme.inset)
                if let notice = model.pullRequests.refreshNotice {
                    Text(notice).font(Theme.Fonts.meta).foregroundStyle(.secondary)
                        .padding(.horizontal, Theme.inset).padding(.bottom, Theme.spacing)
                }
                Divider()
                if presentation.isGenuinelyEmpty {
                    ContentUnavailableView("No Changed Files", systemImage: "arrow.triangle.pull",
                                           description: Text("This pull request changes no files between its merge base and head."))
                } else if presentation.isFilteredEmpty {
                    ContentUnavailableView {
                        Label("No Changes to Show", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("The current filters hide all changed files in this pull request.")
                    } actions: {
                        Button("Show All Files", action: model.clearSourceFilters)
                    }
                } else {
                    List(presentation.changes, selection: $selection) { change in
                        ReviewChangeRow(change: change, isSelected: selection == change.id)
                            .tag(change.id)
                            .help(help(for: change))
                            .listRowBackground(Color.accentColor.opacity(selection == change.id ? 0.08 : 0))
                    }
                    .listStyle(.sidebar)
                    .padding(.top, Theme.spacing)
                }
            }
            .onChange(of: presentation, initial: true) { _, _ in syncSelection(presentation) }
            .onChange(of: model.source?.positionKey) { _, _ in syncSelection(presentation) }
            .onChange(of: selection) { _, id in
                guard let id, id != presentation.selectionID(path: model.source?.path, revision: model.currentRevision),
                      let change = presentation.changes.first(where: { $0.id == id }), !change.isBinary else { return }
                model.openChange(change)
            }
        } else if let number = model.pullRequests.loadingNumber {
            VStack(spacing: Theme.spacing) {
                ProgressView(model.pullRequests.loadingMessage ?? "Opening #\(number)…")
                Button("Cancel") { model.exitPullRequest() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView("No Pull Request", systemImage: "arrow.triangle.pull",
                                   description: Text("Choose a pull request from the toolbar or press ⌘P."))
        }
    }

    private func help(for change: FileChange) -> String {
        var text = "\(change.status.title)\n\(change.path)"
        if change.isBinary { text += "\nBinary file; not shown as text." }
        if let old = change.oldPath { text += " from \(old)" }
        return text
    }

    private func syncSelection(_ presentation: ReviewChangesPresentation) {
        let id = presentation.selectionID(path: model.source?.path, revision: model.currentRevision)
        if id != selection { selection = id }
    }

}
