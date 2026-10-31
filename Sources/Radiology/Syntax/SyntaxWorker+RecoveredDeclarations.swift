import Foundation
import SwiftTreeSitter

extension SyntaxWorker {
    /// Preprocessor branches can contain unmatched braces while each compiled
    /// configuration is valid. Tree-sitter still recognizes the declarator head
    /// even when the enclosing definition is an ERROR rather than a function.
    func recoverFunctionDeclarations(root: Node, data: Data) throws -> [DocumentSymbol] {
        var pending = [root]
        var declarations: [DocumentSymbol] = []
        while let node = pending.popLast() {
            try Task.checkCancellation()
            if node.nodeType == "function_declarator",
               let name = CDeclarationSyntax.name(in: node, requireFunction: true) {
                var end = node.intByteRange.upperBound
                while end < data.count, [9, 10, 13, 32].contains(data[end]) { end += 1 }
                // A call, prototype or function-pointer variable has no body
                // opening immediately after its declarator.
                if end < data.count, data[end] == 123 {
                    declarations.append(DocumentSymbol(name: String(decoding: data[name.intByteRange], as: UTF8.self),
                        kind: "function", byteRange: node.intByteRange.lowerBound..<(end + 1),
                        selectionByteRange: name.intByteRange, depth: 0))
                }
            }
            pending.append(contentsOf: node.childNodes())
        }
        return declarations
    }
}
