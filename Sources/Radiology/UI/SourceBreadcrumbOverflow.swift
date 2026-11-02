import SwiftUI

/// Compaction keeps the complete location and all declaration jumps available.
struct SourceBreadcrumbOverflow: View {
    let rootName: String
    let path: String
    let symbols: [DocumentSymbol]
    let select: (DocumentSymbol) -> Void

    var body: some View {
        Menu {
            Section("Source Path") {
                Text("\(rootName)/\(path)")
            }
            if !symbols.isEmpty {
                Section("Enclosing Declarations") {
                    ForEach(symbols) { symbol in
                        Button(symbol.name) { select(symbol) }
                    }
                }
            }
        } label: {
            Text("…").foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
        .help("\(rootName)/\(path)")
        .accessibilityLabel("Full source path and enclosing declarations")
    }
}
