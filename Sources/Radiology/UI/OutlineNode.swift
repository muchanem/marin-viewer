import Foundation

struct OutlineNode: Identifiable {
    let symbol: DocumentSymbol
    let children: [OutlineNode]
    var id: String { symbol.id }
    var optionalChildren: [OutlineNode]? { children.isEmpty ? nil : children }

    static func forest(from symbols: [DocumentSymbol]) -> [OutlineNode] {
        DocumentSymbol.roots(in: symbols).map { node(for: $0, symbols: symbols) }
    }

    private static func node(for symbol: DocumentSymbol, symbols: [DocumentSymbol]) -> OutlineNode {
        OutlineNode(symbol: symbol,
                    children: symbol.children(in: symbols).map { node(for: $0, symbols: symbols) })
    }
}
