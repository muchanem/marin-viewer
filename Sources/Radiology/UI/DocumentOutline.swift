import Foundation

/// Sidebar ordering only. Original symbols/ranges remain the navigation IDs;
/// source, semantic context, breadcrumbs and gutter retain source order.
struct DocumentOutline {
    /// Paths matter even when two files have identical bytes and symbols.
    struct InputKey: Equatable {
        let path: String?
        let syntaxPath: String?
        let sourceIdentity: SourceContentIdentity?
        let symbols: [DocumentSymbol]
    }

    struct Function: Identifiable {
        let symbol: DocumentSymbol
        let lineCount: Int
        var id: String { symbol.id }
    }

    let path: String
    let sourceIdentity: SourceContentIdentity
    let functions: [Function]
    let declarations: [OutlineNode]

    init(symbols: [DocumentSymbol], buffer: SourceBuffer) {
        path = buffer.path
        sourceIdentity = SourceContentIdentity(buffer.data)
        functions = symbols.enumerated().filter { SyntaxSnapshot.callableKinds.contains($0.element.kind) }
            .map { (entry: Function(symbol: $0.element, lineCount: Self.lineCount(of: $0.element, in: buffer)), order: $0.offset) }
            .sorted {
                if $0.entry.lineCount != $1.entry.lineCount { return $0.entry.lineCount > $1.entry.lineCount }
                if $0.entry.symbol.byteRange.lowerBound != $1.entry.symbol.byteRange.lowerBound {
                    return $0.entry.symbol.byteRange.lowerBound < $1.entry.symbol.byteRange.lowerBound
                }
                return $0.order < $1.order
            }
            .map(\.entry)
        // Removing callable containers promotes their non-callable descendants
        // to the nearest remaining container, so nested declarations stay usable.
        declarations = OutlineNode.forest(from: symbols.filter { !SyntaxSnapshot.callableKinds.contains($0.kind) })
    }

    static func lineCount(of symbol: DocumentSymbol, in buffer: SourceBuffer) -> Int {
        let start = symbol.byteRange.lowerBound
        // Ranges are half-open: an end at the next line's start is not a line
        // of the declaration. Use bytes, not string/UTF-16 character counts.
        let last = max(start, symbol.byteRange.upperBound - 1)
        return buffer.line(atByte: last) - buffer.line(atByte: start) + 1
    }
}
