import SwiftUI

/// Toolbar menu: the local checkout or one of the recent pull requests, the
/// number sheet, and a refresh. Its label names the active review.
struct PullRequestMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Menu {
            if model.isReviewing || model.pullRequests.isLoading {
                Button("Exit PR", systemImage: "arrow.uturn.backward", action: model.exitPullRequest)
                    .help("Exit pull request review and return to the local checkout, or cancel an opening review.")
                Divider()
            }
            Picker("Pull Request", selection: $model.pullRequestSelection) {
                if !model.isReviewing && !model.pullRequests.isLoading {
                    Text("Local Checkout").tag(Optional<Int>.none)
                }
                if let review = model.review, !model.pullRequests.recent.contains(where: { $0.number == review.number }) {
                    Text("#\(review.number)  \(review.title) · \(review.summary.stateTitle)").tag(Optional(review.number))
                }
                if !model.pullRequests.recent.isEmpty {
                    Divider()
                    ForEach(model.pullRequests.recent) { summary in
                        Text("#\(summary.number)  \(summary.title) · \(summary.stateTitle)").tag(Optional(summary.number))
                    }
                }
            }
            .pickerStyle(.inline)
            Divider()
            Button("Open Pull Request…", action: model.showPullRequestNumber).disabled(!model.pullRequests.canReview)
            Button("Refresh PR", action: model.refreshCurrentPR).disabled(!model.canRefreshPR)
            Button("Refresh List", action: model.refreshPullRequests)
                .disabled(!model.pullRequests.canReview || model.pullRequests.listPhase == .loading)
            if case .failed(let reason) = model.pullRequests.listPhase {
                Text(reason)
            }
        } label: {
            Label(title, systemImage: "arrow.triangle.pull")
                .labelStyle(.titleAndIcon)
        }
        .labelStyle(.titleAndIcon)
        .menuIndicator(.visible)
        .disabled(!model.pullRequests.canReview && !model.isReviewing && !model.pullRequests.isLoading)
        .help(help)
        .accessibilityLabel("Pull request: \(title)")
    }

    private var title: String {
        if let number = model.pullRequests.loadingNumber { return "#\(number)…" }
        if let review = model.review { return "#\(review.number)" }
        return "Pull Request"
    }

    private var help: String {
        switch model.pullRequests.listPhase {
        case .unavailable(let reason): reason
        case .loading: "Listing pull requests…"
        case .failed(let reason): reason
        case .loaded: model.review.map { "#\($0.number) \($0.title). Choose Exit PR to leave the review." } ?? "Review a pull request of this repository (⌘P for a number)"
        }
    }
}
