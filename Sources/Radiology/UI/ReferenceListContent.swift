import SwiftUI

/// The reference rows of the declaration region, grouped by file: one line
/// each, with a disclosure chevron for the surrounding source.
struct ReferenceListContent: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.context.references {
        case .unavailable:
            ContextStatusLine(text: model.referencesUnavailableStatus, detail: model.referencesUnavailableReason)
        case .loading:
            ProgressView("Finding references…")
                .controlSize(.small)
                .font(Theme.Fonts.meta)
        case .failed(let message):
            ContextStatusLine(text: "References unavailable", detail: message, systemImage: "exclamationmark.triangle")
        case .loaded(let results):
            ReferenceCoverageView(results: results)
            ForEach(results.groups) { group in
                Section {
                    ForEach(group.hits) { hit in
                        ReferenceRow(hit: hit, isExpanded: model.context.isReferenceExpanded(hit.id)) {
                            model.context.toggleReference(hit.id)
                        }
                        .tag(hit.id)
                    }
                } header: {
                    ReferenceFileHeader(group: group)
                }
            }
        }
    }
}
