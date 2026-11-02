import SwiftUI
import ViewerCore

/// The sticky header of a file card (the demo's `.fhead`): collapse
/// chevron, path with a quiet directory, the file's one-sentence change
/// description with "More", the excerpt's lines in By step mode, counts,
/// and the Whole file / Diff only switch.
struct DiffFileHeader: View {
    let model: DiffReaderModel
    let card: DiffReaderModel.Card
    let file: PRFileReview

    private var collapsed: Bool { model.isCollapsed(card.path) }
    private var wholeFile: Bool { model.wholeFile.contains(card.path) }
    private var layerKey: String { "f:\(card.path)" }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button {
                model.toggleCollapsed(card.path)
            } label: {
                Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(nsColor: DiffReaderStyle.muted))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            .help(collapsed ? "Expand file" : "Collapse file")
            .accessibilityLabel(collapsed ? "Expand \(card.path)" : "Collapse \(card.path)")

            VStack(alignment: .leading, spacing: 2) {
                path
                if let description = file.description {
                    LayeredDescriptionText(layers: Layers(l1: description.l1, l2: description.l2), level: model.layer(layerKey),
                                           style: .inline) { model.setLayer(layerKey, to: $0) }
                }
                if let excerpt = card.excerpt {
                    Text("lines \(excerpt.lines.lowerBound) to \(excerpt.lines.upperBound)")
                        .font(.caption.monospaced())
                        .foregroundStyle(Color(nsColor: DiffReaderStyle.muted))
                        .help(excerpt.problem ?? (excerpt.source == .functions
                            ? "Resolved from \(excerpt.excerpt.functions.joined(separator: ", ")) at the head"
                            : "Lines from the code path"))
                }
            }
            Spacer(minLength: 8)
            counts
            if !file.diff.rows.isEmpty {
                Button(wholeFile ? "Diff only" : "Whole file") { model.toggleWholeFile(card.path) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: DiffReaderStyle.headerFill))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: DiffReaderStyle.cardCornerRadius,
                                          bottomLeadingRadius: collapsed ? DiffReaderStyle.cardCornerRadius : 0,
                                          bottomTrailingRadius: collapsed ? DiffReaderStyle.cardCornerRadius : 0,
                                          topTrailingRadius: DiffReaderStyle.cardCornerRadius))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: DiffReaderStyle.cardCornerRadius,
                                   bottomLeadingRadius: collapsed ? DiffReaderStyle.cardCornerRadius : 0,
                                   bottomTrailingRadius: collapsed ? DiffReaderStyle.cardCornerRadius : 0,
                                   topTrailingRadius: DiffReaderStyle.cardCornerRadius)
                .strokeBorder(Color(nsColor: DiffReaderStyle.rule))
        }
        .contextMenu {
            Button("Ask About This File") { model.ask(model.fileChip(path: card.path)) }
            Button("Open File in New Window") { model.openInNewWindow(DiffCodeTarget(path: card.path)) }
            if !file.diff.rows.isEmpty, !wholeFile {
                Button("Show Whole File") { model.showWholeFile(card.path) }
            }
        }
    }

    private var path: some View {
        let slash = card.path.lastIndex(of: "/").map { card.path.index(after: $0) } ?? card.path.startIndex
        var text = AttributedString(String(card.path[..<slash]))
        text.foregroundColor = Color(nsColor: DiffReaderStyle.muted)
        var name = AttributedString(String(card.path[slash...]))
        name.foregroundColor = Color(nsColor: DiffReaderStyle.ink)
        return Text(text + name)
            .font(.callout.monospaced())
            .lineLimit(1)
            .truncationMode(.head)
            .help(card.path)
    }

    private var counts: some View {
        var added = AttributedString("+\(file.diff.additions)")
        added.foregroundColor = Color(nsColor: DiffReaderStyle.ok)
        var deleted = AttributedString(" −\(file.diff.deletions)")
        deleted.foregroundColor = Color(nsColor: DiffReaderStyle.bad)
        return Text(added + deleted)
            .font(.caption.monospacedDigit())
            .fixedSize()
            .accessibilityLabel("\(file.diff.additions) added, \(file.diff.deletions) deleted")
    }
}

/// The By step header: kicker, title and the step's layered summary.
struct DiffStepHeader: View {
    let model: DiffReaderModel
    let step: ResolvedStep

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let position = model.stepPosition {
                Text("Step \(position.index) of \(position.count)".uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Color(nsColor: DiffReaderStyle.muted))
            }
            Text(step.step.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(nsColor: DiffReaderStyle.ink))
            LayeredDescriptionText(layers: step.step.layers, level: model.layer("s:\(step.id)"), style: .block) {
                model.setLayer("s:\(step.id)", to: $0)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button("Ask About This Step") { model.ask(model.stepChip(step)) }
        }
    }
}

/// The By file header.
struct DiffAllFilesHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("All changed files".uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(Color(nsColor: DiffReaderStyle.muted))
            Text("Diffs with \(DiffVisibility.contextLines) lines of context")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Color(nsColor: DiffReaderStyle.ink))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
