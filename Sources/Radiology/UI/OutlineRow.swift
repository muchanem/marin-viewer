import SwiftUI

/// One declaration in the outline. Indentation carries nesting; the symbol
/// gives the kind at a glance without introducing another type size or weight.
struct OutlineRow: View {
    let symbol: DocumentSymbol
    var lineCount: Int?
    /// In a pull request review: the declaration contains changed lines.
    var isChanged = false
    let select: () -> Void

    var body: some View {
        HStack(spacing: Theme.spacing) {
            Button(symbol.name, systemImage: Self.icon(for: symbol.kind), action: select)
                .font(Theme.Fonts.body)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .buttonStyle(.plain)
                .help("Go to \(symbol.name)")
            if isChanged {
                Circle().fill(.tint).frame(width: 6, height: 6)
                    .help("Contains lines changed by the pull request")
                    .accessibilityLabel("Changed in this pull request")
            }
            if let lineCount {
                Text("\(lineCount) L")
                    .font(Theme.Fonts.meta.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .help("\(lineCount) \(lineCount == 1 ? "line" : "lines"), signature through declaration end")
                    .accessibilityLabel("\(lineCount) \(lineCount == 1 ? "line" : "lines")")
            }
        }
    }

    static func icon(for kind: String) -> String {
        switch kind {
        case "type", "struct": "square.stack.3d.up"
        case "protocol": "point.3.connected.trianglepath.dotted"
        case "enum": "list.bullet.rectangle"
        case "case": "circle.hexagongrid"
        case "typealias": "arrow.triangle.branch"
        case "module", "extension": "shippingbox"
        case "initializer", "deinitializer": "plusminus"
        case "property", "variable": "cube"
        case "constant": "lock"
        case "macro": "number"
        case "method": "function"
        default: "function"
        }
    }
}
