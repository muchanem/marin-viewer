import SwiftUI

struct SourceBreadcrumbTrail: View {
    let rootName: String
    let path: String
    let fileName: String
    var directories: [String] = []
    var visibleRoot: String? = nil
    var hasOmissions = false
    var showsFile = true
    let symbols: [DocumentSymbol]
    let visibleSymbols: [DocumentSymbol]
    let select: (DocumentSymbol) -> Void

    var body: some View {
        HStack(spacing: Theme.breadcrumbSpacing) {
            if let visibleRoot {
                Label(visibleRoot, systemImage: "externaldrive")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                SourceBreadcrumbSeparator()
            }
            if hasOmissions {
                SourceBreadcrumbOverflow(rootName: rootName, path: path, symbols: symbols, select: select)
                SourceBreadcrumbSeparator()
            }
            ForEach(Array(directories.enumerated()), id: \.offset) { _, directory in
                Text(directory).foregroundStyle(.secondary).lineLimit(1)
                SourceBreadcrumbSeparator()
            }
            if showsFile {
                Text(fileName)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("\(rootName)/\(path)")
            }
            ForEach(visibleSymbols) { symbol in
                if showsFile || symbol.id != visibleSymbols.first?.id { SourceBreadcrumbSeparator() }
                Button(symbol.name) { select(symbol) }
                    .buttonStyle(.plain)
                    .fontWeight(symbol.id == symbols.last?.id ? .medium : .regular)
                    .foregroundStyle(symbol.id == symbols.last?.id ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(symbol.id == symbols.last?.id ? 1 : 0)
                    .help("Go to \(symbol.name)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
