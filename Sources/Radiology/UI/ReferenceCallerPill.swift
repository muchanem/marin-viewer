import SwiftUI

struct ReferenceCallerPill: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    let caller: ReferenceCaller

    var body: some View {
        Button(action: openCaller) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.spacing / 2) {
                    Text(caller.name)
                        .font(Theme.Fonts.codeSnippetEmphasis)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Text(caller.line, format: .number.grouping(.never))
                        .font(Theme.Fonts.snippetLineNumber)
                        .foregroundStyle(.secondary)
                }
                Text(URL(filePath: caller.location.path).lastPathComponent)
                    .font(Theme.Fonts.inspectorMetadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, Theme.callerPillHorizontalInset)
            .padding(.vertical, Theme.callerPillVerticalInset)
            .background(color.opacity(fillOpacity), in: .capsule)
            .overlay {
                Capsule().strokeBorder(color.opacity(strokeOpacity), lineWidth: differentiateWithoutColor ? 1.5 : 0.75)
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help("\(caller.location.path):\(caller.line)")
        .accessibilityLabel("\(caller.name), caller level \(caller.depth), \(caller.location.path), line \(caller.line)")
    }

    private var color: Color { CallTreePalette.colors[CallTreePalette.slot(method: caller.name, file: caller.location.path)] }
    private var fillOpacity: Double { colorScheme == .dark ? 0.24 : 0.12 }
    private var strokeOpacity: Double { contrast == .increased || differentiateWithoutColor ? 0.75 : (colorScheme == .dark ? 0.5 : 0.3) }

    private func openCaller() { model.commitCaller(caller) }
}
