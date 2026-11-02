import SwiftUI

/// The main column of an open PR: the diff reader once the review document has loaded. Until
/// then, or when the document fails to load, `ViewerMainPlaceholder` lists the step's excerpts
/// from the wordbase so the step sidebar and strip still have something to point at.
struct ViewerMainView: View {
    @Environment(ViewerStore.self) private var store

    var body: some View {
        if let reader = store.diffReader {
            DiffReaderView(model: reader)
        } else {
            ViewerMainPlaceholder()
                .safeAreaInset(edge: .top, spacing: 0) { status }
        }
    }

    @ViewBuilder private var status: some View {
        HStack(spacing: 6) {
            if let error = store.documentError {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                Text(verbatim: "The diff could not be loaded: \(error)").lineLimit(2)
            } else {
                ProgressView().controlSize(.small)
                Text("Loading the diff from the Marin checkout…")
            }
            Spacer(minLength: 0)
        }
        .font(ViewerFonts.meta)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
