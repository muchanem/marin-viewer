import Foundation

actor RepositoryWorker {
    private let commands = CommandRunner()
    static let excludedDirectories: Set<String> = [".git", ".build", "build", "dist", "node_modules", "vendor", "DerivedData", "target", ".DS_Store"]

    func open(_ folder: URL) async throws -> RepositorySnapshot {
        let folder = folder.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw BrowserError.message("Choose a folder to browse.")
        }
        var root = folder
        var isGit = false
        var paths: [String] = []
        if let git = ToolLocator.executable("git"),
           let data = try? await commands.run(git, arguments: ["rev-parse", "--show-toplevel"], directory: folder),
           let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .newlines), !path.isEmpty {
            root = URL(filePath: path, directoryHint: .isDirectory)
            let files = try await commands.run(git, arguments: ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], directory: root)
            paths = files.split(separator: 0).compactMap { String(data: Data($0), encoding: .utf8) }
            isGit = true
        } else {
            try Task.checkCancellation()
            paths = try enumerate(root)
        }
        let files = Set(paths).filter { path in
            !path.split(separator: "/").contains { Self.excludedDirectories.contains(String($0)) }
            && FileManager.default.fileExists(atPath: root.appending(path: path).path)
        }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { RepositoryFile(path: $0) }
        return RepositorySnapshot(root: root, files: files, tree: FileNode.tree(files: files), isGit: isGit)
    }

    private func enumerate(_ root: URL) throws -> [String] {
        var paths: [String] = []
        // Relative names avoid macOS /var and /private/var URL alias differences.
        guard let enumerator = FileManager.default.enumerator(atPath: root.path) else {
            throw BrowserError.message("This folder could not be read.")
        }
        for case let path as String in enumerator {
            try Task.checkCancellation()
            let url = root.appending(path: path)
            if Self.excludedDirectories.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true { paths.append(path) }
        }
        return paths
    }
}
