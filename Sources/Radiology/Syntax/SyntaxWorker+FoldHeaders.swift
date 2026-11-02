import SwiftTreeSitter

extension SyntaxWorker {
    func foldHeaders(root: Node, languageID: String) -> [FoldHeaderOwnership] {
        guard languageID == "rust" || languageID == "python" else { return [] }
        var result: [FoldHeaderOwnership] = []
        var pending = [root]
        while let node = pending.popLast() {
            let children = node.childNodes()
            if languageID == "python", node.nodeType == "decorated_definition",
               let definition = node.child(byFieldName: "definition"), definition.nodeType == "function_definition" {
                result.append(FoldHeaderOwnership(declarationByteRange: definition.intByteRange,
                                                   annotatedByteRange: node.intByteRange))
            }
            if languageID == "rust" {
                for (index, child) in children.enumerated() where child.nodeType == "function_item" {
                    var first = child.intByteRange.lowerBound
                    var cursor = index - 1
                    while cursor >= 0 {
                        let previous = children[cursor]
                        if previous.nodeType == "attribute_item" { first = previous.intByteRange.lowerBound }
                        else if previous.nodeType != "line_comment" && previous.nodeType != "block_comment" { break }
                        cursor -= 1
                    }
                    if first < child.intByteRange.lowerBound {
                        result.append(FoldHeaderOwnership(declarationByteRange: child.intByteRange,
                            annotatedByteRange: first..<child.intByteRange.upperBound))
                    }
                }
            }
            if node.nodeType != "token_tree" { pending.append(contentsOf: children) }
        }
        return result
    }
}
