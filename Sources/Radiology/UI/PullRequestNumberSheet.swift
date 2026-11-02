import SwiftUI

/// ⌘P: type a pull request number. The same shape as Go to Line.
struct PullRequestNumberSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Theme.inset) {
            Text("Open Pull Request").font(Theme.Fonts.heading)
            TextField("Pull request number", value: $model.pullRequestNumberInput, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder).focused($focused).onSubmit(model.openPullRequestFromSheet)
            Text(hint).font(Theme.Fonts.meta).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open", action: model.openPullRequestFromSheet).keyboardShortcut(.defaultAction)
                    .disabled(model.pullRequestNumberInput < 1)
            }
        }.padding(Theme.inset * 2).frame(width: 340).task { focused = true }
    }

    private var hint: String {
        if let repository = model.pullRequests.repository { return repository.nameWithOwner }
        return "Any pull request of the attached repository, open, merged, or closed."
    }
}
