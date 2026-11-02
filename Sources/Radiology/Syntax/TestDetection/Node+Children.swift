import SwiftTreeSitter

extension Node {
    /// Direct children in order through a tree cursor. `child(at:)` and
    /// sibling links walk from the parent each time, which is quadratic over
    /// a file with thousands of items.
    func childNodes(namedOnly: Bool = true) -> [Node] {
        let cursor = treeCursor
        guard cursor.goToFirstChild() else { return [] }
        var nodes: [Node] = []
        repeat {
            if let node = cursor.currentNode, !namedOnly || node.isNamed { nodes.append(node) }
        } while cursor.gotoNextSibling()
        return nodes
    }

    var intByteRange: Range<Int> { Int(byteRange.lowerBound)..<Int(byteRange.upperBound) }

    /// The first node of `type` in a depth-first walk below this node.
    func firstDescendant(ofType type: String) -> Node? {
        for child in childNodes() {
            if child.nodeType == type { return child }
            if let found = child.firstDescendant(ofType: type) { return found }
        }
        return nil
    }
}
