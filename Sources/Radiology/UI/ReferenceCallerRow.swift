import SwiftUI

struct ReferenceCallerRow: View {
    let caller: ReferenceCaller

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: Theme.spacing / 2) {
                VStack(alignment: .leading, spacing: 2) {
                    Image(systemName: caller.depth == 0 ? "function" : "arrow.turn.down.right")
                        .font(Theme.Fonts.inspectorMetadata)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    if caller.depth > 4 {
                        Text("L\(caller.depth)")
                            .font(Theme.Fonts.snippetLineNumber)
                            .foregroundStyle(.secondary)
                            .help("Caller level \(caller.depth)")
                    }
                }
                .padding(.top, Theme.callerPillVerticalInset)
                .frame(width: Theme.disclosureWidth, alignment: .leading)
                ReferenceCallerPill(caller: caller)
            }
            if let note = caller.note {
                Text(note)
                    .font(Theme.Fonts.inspectorMetadata)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Theme.disclosureWidth + Theme.spacing / 2)
            }
        }
        // Deep paths keep room for names. VoiceOver and the tooltip retain
        // the full depth even after indentation reaches its visual limit.
        .padding(.leading, Double(min(caller.depth, 4)) * Theme.outlineIndent)
        .help("Caller level \(caller.depth) · \(caller.location.path):\(caller.line)")
    }

}
