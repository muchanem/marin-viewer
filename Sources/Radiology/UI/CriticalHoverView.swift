import SwiftUI

/// The automatic hover popover in Critical mode: the hovered callable, a
/// link to its definition (or an honest "external"), then its compact
/// frontier. Rows are plain buttons so the pointer can move from the source
/// into the popover and click. Native host tracking covers the whole popup;
/// loading updates keep that host and the button hit regions intact.
struct CriticalHoverView: View {
    let content: HoverPopoverContent
    let navigate: (SemanticPosition?, String) -> Void

    var body: some View {
        let presentation = content.presentation
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HoverDestinationRow(name: presentation.displayName, systemImage: "function",
                                detail: presentation.definition == nil
                                    ? (presentation.externalPackage?.split(separator: " ").first.map(String.init) ?? "external") : "Definition",
                                definition: presentation.definition, navigate: navigate)
            Divider()
            HoverFrontierRows(phase: presentation.phase, navigate: navigate)
        }
        .padding(Theme.inset)
        .frame(width: Theme.hoverPopoverWidth, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Critical operations of \(presentation.displayName)")
    }
}

/// Rows without the environment model: the popover is hosted by AppKit.
private struct HoverFrontierRows: View {
    let phase: CriticalSummaryModel.Phase
    let navigate: (SemanticPosition?, String) -> Void

    var body: some View {
        switch phase {
        case .loading:
            ProgressView("Summarizing…").controlSize(.small).font(Theme.Fonts.meta)
        case .loaded(let frontier):
            ContextStatusLine(text: frontier.statusLine, detail: frontier.statusDetail,
                              systemImage: frontier.coverage.isComplete ? "checkmark.circle" : "circle.dotted")
            let rows = frontier.directCritical.map {
                CriticalPath(callee: $0.callee, displayName: $0.displayName, kind: $0.kind, classification: $0.classification,
                             definition: $0.definition, via: [], depth: 1)
            } + frontier.paths
            ForEach(rows.prefix(Theme.maxHoverRows)) { row in
                HoverDestinationRow(name: row.displayName, systemImage: row.kind.systemImage,
                                    detail: row.definition.map { "\(($0.path as NSString).lastPathComponent):\($0.range.startLine + 1)" }
                                        ?? (SCIPSymbolString.package(of: row.callee.symbol)?.split(separator: " ").first.map(String.init) ?? "external"),
                                    via: row.viaDescription, definition: row.definition, navigate: navigate)
            }
            if rows.count > Theme.maxHoverRows {
                ContextStatusLine(text: "+\(rows.count - Theme.maxHoverRows) more", detail: rows.dropFirst(Theme.maxHoverRows).map(\.displayName).joined(separator: ", "))
            }
        }
    }
}
