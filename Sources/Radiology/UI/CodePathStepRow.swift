import SwiftUI

struct CodePathStepRow: View {
    let step: CodePathStep
    let number: Int

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            Text(number, format: .number.grouping(.never))
                .font(Theme.Fonts.meta.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.spacing / 2) {
                Text(step.function).font(Theme.Fonts.heading.monospaced())
                    .lineLimit(1).truncationMode(.tail)
                Text(step.description).font(Theme.Fonts.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(step.path).font(Theme.Fonts.identifier)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.spacing / 2)
        .contentShape(.rect)
        .help("\(step.function)\n\(step.description)\n\(step.path)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(step.function). \(step.description). \(step.path)")
    }
}
