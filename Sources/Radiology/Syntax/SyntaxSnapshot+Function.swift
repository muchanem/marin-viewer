import Foundation

extension SyntaxSnapshot {
    /// Tree-sitter symbol kinds that are callables with their own body.
    static let callableKinds: Set<String> = ["function", "method", "initializer", "deinitializer"]

    /// The innermost function, method, or initializer whose declaration
    /// (signature through body, half-open) contains the byte. Types, `impl`
    /// blocks, modules, and properties never qualify, so the caret between
    /// methods yields nil rather than the whole container.
    func innermostFunction(at byte: Int) -> DocumentSymbol? {
        var best: DocumentSymbol?
        for symbol in symbols where Self.callableKinds.contains(symbol.kind) && symbol.byteRange.contains(byte) {
            if best == nil || symbol.byteRange.count < best!.byteRange.count { best = symbol }
        }
        return best
    }

    /// Match this declaration's own body, rather than a closure/default
    /// argument or nested function that also happens to lie inside it.
    func enclosingFunctionFold(at byte: Int) -> (function: DocumentSymbol, fold: SourceFold)? {
        guard let function = innermostFunction(at: byte),
              let fold = folds.filter({
                  $0.kind == "function" && $0.byteRange.lowerBound >= function.selectionByteRange.upperBound
                      && $0.byteRange.upperBound == function.byteRange.upperBound
              }).min(by: { $0.byteRange.lowerBound < $1.byteRange.lowerBound }) else { return nil }
        return (function, fold)
    }
}
