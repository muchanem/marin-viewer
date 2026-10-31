import Foundation

struct FileNode: Identifiable, Sendable {
    let path: String
    let name: String
    var children: [FileNode]?
    var id: String { path }
    var isDirectory: Bool { children != nil }

    /// Add a temporarily revealed document while retaining the filtered tree.
    /// Only its ancestor chain is copied; unrelated branches remain intact.
    static func revealing(_ file: RepositoryFile, in nodes: [FileNode]) -> [FileNode] {
        let components = file.path.split(separator: "/").map(String.init)
        guard !components.isEmpty else { return nodes }
        func insert(_ nodes: [FileNode], depth: Int, prefix: String) -> [FileNode] {
            let name = components[depth]
            let path = prefix + name
            let directory = depth + 1 < components.count
            var result = nodes
            if let index = result.firstIndex(where: { $0.path == path }) {
                if directory { result[index].children = insert(result[index].children ?? [], depth: depth + 1, prefix: path + "/") }
            } else {
                let node = FileNode(path: path, name: name, children: directory ? insert([], depth: depth + 1, prefix: path + "/") : nil)
                let index = result.firstIndex { existing in
                    node.isDirectory != existing.isDirectory ? node.isDirectory : node.name.localizedStandardCompare(existing.name) == .orderedAscending
                } ?? result.count
                result.insert(node, at: index)
            }
            return result
        }
        return insert(nodes, depth: 0, prefix: "")
    }

    static func tree(files: [RepositoryFile], prefix: String = "") -> [FileNode] {
        let groups = Dictionary(grouping: files) { file in
            String(file.path.dropFirst(prefix.count).split(separator: "/", maxSplits: 1).first ?? "")
        }
        return groups.compactMap { name, files in
            guard !name.isEmpty else { return nil }
            let path = prefix + name
            let directory = files.contains { $0.path != path }
            return FileNode(path: path, name: name, children: directory ? tree(files: files, prefix: path + "/") : nil)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}
