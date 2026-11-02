import SwiftUI

/// One Files-tree node; directories recurse through a disclosure group whose
/// expansion is keyed by path, so filtering never collapses the tree.
struct FileTreeRow: View {
    let node: FileNode
    let expansion: FileTreeExpansion
    let root: URL

    var body: some View {
        if let children = node.children {
            DisclosureGroup(isExpanded: expansion.binding(for: node.path)) {
                ForEach(children) { child in
                    FileTreeRow(node: child, expansion: expansion, root: root)
                }
            } label: {
                FileTreeLabel(title: node.name, path: node.path, isDirectory: true, root: root)
            }
        } else {
            FileTreeLabel(title: node.name, path: node.path, isDirectory: false, root: root)
                .id(node.path)
        }
    }
}
