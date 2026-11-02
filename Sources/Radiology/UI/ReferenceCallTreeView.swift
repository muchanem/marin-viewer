import SwiftUI

struct ReferenceCallTreeView: View {
    @Environment(AppModel.self) private var model
    let referenceID: ReferenceHit.ID

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing / 2) {
            Text("Callers")
                .font(Theme.Fonts.regionTitle)
                .foregroundStyle(.secondary)
                .help("Calls traced backward from the containing function using this index. Dynamic dispatch, unindexed code, and callback invocations may be missing.")
            switch model.context.referenceCallTrees[referenceID] {
            case .loading:
                ProgressView("Tracing callers…")
                    .controlSize(.small)
                    .font(Theme.Fonts.inspectorMetadata)
            case .loaded(let tree):
                ForEach(tree.callers) { caller in
                    ReferenceCallerRow(caller: caller)
                }
                if !tree.notices.isEmpty {
                    ContextStatusLine(text: "Partial caller tree", detail: tree.notices.joined(separator: "\n"))
                }
                if tree.hasMore {
                    Button("Trace more callers", action: traceMore)
                        .buttonStyle(.link)
                        .font(Theme.Fonts.meta)
                        .help("Continue tracing beyond the first \(tree.budget) entries")
                }
            case .failed(let message):
                ContextStatusLine(text: "Callers unavailable", detail: message, systemImage: "exclamationmark.triangle")
            case nil:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func traceMore() { model.context.traceMoreCallers(id: referenceID) }
}
